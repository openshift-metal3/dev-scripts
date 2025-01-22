package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"time"

	"github.com/adrg/xdg"
	"github.com/charmbracelet/bubbles/help"
	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/progress"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/spf13/cobra"
	"golang.org/x/net/html"
)

var logBuffer = bytes.NewBufferString("")
var logger = log.New(logBuffer, "", log.LstdFlags)

const BUILDS_PER_JOB = 10

const baseArtifactsUrl = "https://gcsweb-ci.apps.ci.l2s4.p1.openshiftapps.com/gcs/origin-ci-test/logs"

var buildIDRegex = regexp.MustCompile(`.*/(\d+)/`)

var versionStyle = lipgloss.NewStyle().Width(24).MarginBottom(2).Align(lipgloss.Center)
var versionStyleSelected = lipgloss.NewStyle().Width(24).MarginBottom(2).Bold(true).Align(lipgloss.Center)
var jobStyleSelected = lipgloss.NewStyle().Bold(true).Background(lipgloss.Color("#0284c7"))
var jobTypeStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#a1a1aa"))

var green = lipgloss.NewStyle().Background(lipgloss.Color("#16a34a"))
var red = lipgloss.NewStyle().Background(lipgloss.Color("#dc2626"))
var border = lipgloss.NewStyle().BorderStyle(lipgloss.NormalBorder()).Padding(1)
var selectedBorder = lipgloss.NewStyle().BorderStyle(lipgloss.ThickBorder()).Padding(1)

type Started struct {
	Timestamp int64 `json:"timestamp"`
}

type Finished struct {
	Timestamp int64  `json:"timestamp"`
	Passed    bool   `json:"passed"`
	Result    string `json:"result"`
	Revision  string `json:"revision"`
}

type Build struct {
	ID       string     `json:"id"`
	Started  *time.Time `json:"started"`
	Finished *time.Time `json:"finished"`
	Passed   bool       `json:"passed"`
	Result   string     `json:"result"`
}

func (b *Build) IsFinished() bool {
	return b.Finished != nil
}

type Cache struct {
	LastUpdated time.Time    `json:"last_updated"`
	OCPVersions []OCPVersion `json:"ocp_versions"`
}

type PeriodicJob struct {
	Optional bool
	Upgrade  bool
	ProwJob  `json:"prowJob"`
}

type ProwJob struct {
	Name string
}

type ReleaseInfo struct {
	Name   string
	Verify map[string]PeriodicJob
}

type Job struct {
	Name     string  `json:"name"`
	ProwName string  `json:"prow_name"`
	Optional bool    `json:"optional"`
	Upgrade  bool    `json:"upgrade"`
	Builds   []Build `json:"builds"`
}

type Jobs []Job

func (j Jobs) Len() int {
	return len(j)
}

func (j Jobs) Swap(a, b int) {
	j[a], j[b] = j[b], j[a]
}

func (j Jobs) Less(a, b int) bool {
	res := strings.Compare(j[a].Name, j[b].Name)
	return res < 0
}

func (j Job) HistoryLink() string {
	return fmt.Sprintf("https://prow.ci.openshift.org/job-history/gs/test-platform-results/logs/%s", j.ProwName)
}

type OCPVersion struct {
	Name string `json:"name"`
	Jobs []Job  `json:"jobs"`
}

func Scrape(url string, pattern *regexp.Regexp) ([]string, error) {
	r, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer r.Body.Close()

	res := []string{}
	z := html.NewTokenizer(r.Body)

	for {
		tokenType := z.Next()

		if tokenType == html.ErrorToken {
			break
		}
		if tokenType != html.StartTagToken {
			continue
		}

		token := z.Token()
		if token.Data != "a" {
			continue
		}

		if len(token.Attr) == 0 || token.Attr[0].Key != "href" {
			continue
		}

		matches := pattern.FindStringSubmatch(token.Attr[0].Val)
		if matches == nil {
			continue
		}

		res = append(res, matches[1])
	}

	return res, nil
}

func FetchRemoteFile(url string) ([]byte, error) {
	r, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer r.Body.Close()

	body, err := io.ReadAll(r.Body)
	if err != nil {
		return nil, err
	}

	return body, nil
}

func GetBuild(id string, job Job) (Build, error) {
	buildUrl := fmt.Sprintf("%s/%s/%s", baseArtifactsUrl, job.Name, id)
	b := Build{
		ID: id,
	}

	startedBytes, err := FetchRemoteFile(fmt.Sprintf("%s/started.json", buildUrl))
	if err != nil {
		return Build{}, err
	}

	var started Started

	err = json.Unmarshal(startedBytes, &started)
	if err != nil {
		return Build{}, err
	}

	startedTime := time.Unix(started.Timestamp, 0)
	b.Started = &startedTime

	finishedBytes, err := FetchRemoteFile(fmt.Sprintf("%s/finished.json", buildUrl))
	if err != nil {
		return Build{}, err
	}

	var finished Finished
	err = json.Unmarshal(finishedBytes, &finished)

	if err != nil {
		return Build{}, err
	}

	finishedTime := time.Unix(finished.Timestamp, 0)
	b.Finished = &finishedTime

	b.Passed = finished.Passed
	b.Result = finished.Result

	return b, nil
}

func FetchAllBuildIds(job Job) (buildIds []string, err error) {
	url := fmt.Sprintf("%s/%s/", baseArtifactsUrl, job.Name)
	buildIds, err = Scrape(url, buildIDRegex)
	if err != nil {
		return nil, err
	}

	sort.Slice(buildIds, func(i, j int) bool {
		return buildIds[i] > buildIds[j]
	})
	return buildIds, nil
}

func GetAllBuilds(job Job) ([]Build, error) {
	builds := []Build{}

	buildIds, err := FetchAllBuildIds(job)

	if err != nil {
		return nil, err
	}

	for i, id := range buildIds {
		if i >= BUILDS_PER_JOB {
			break
		}

		b, err := GetBuild(id, job)

		if err != nil {
			return builds, err
		}

		if !b.IsFinished() {
			continue
		}

		builds = append(builds, b)
	}

	return builds, nil
}

func GetBuildsSince(job Job, from string) ([]Build, error) {
	buildIds, err := FetchAllBuildIds(job)
	if err != nil {
		return nil, err
	}

	result := []Build{}

	for _, id := range buildIds {
		if id <= from {
			continue
		}

		b, err := GetBuild(id, job)
		if err != nil {
			return result, err
		}

		if !b.IsFinished() {
			continue
		}

		result = append(result, b)
	}

	return result, nil
}

func LoadOCPVersionConfig(releaseRepoPath string, requestedVersions []string) ([]OCPVersion, error) {
	versions := []OCPVersion{}

	for _, requestedVersion := range requestedVersions {

		releaseInfoPath := path.Join(releaseRepoPath, "core-services/release-controller/_releases/", fmt.Sprintf("release-ocp-%s.json", requestedVersion))
		if _, err := os.Stat(releaseInfoPath); os.IsNotExist(err) {
			return versions, fmt.Errorf("path does not exist: %s", releaseInfoPath)
		}

		releaseInfoBytes, err := os.ReadFile(releaseInfoPath)
		if err != nil {
			return versions, err
		}

		var releaseInfo ReleaseInfo

		err = json.Unmarshal(releaseInfoBytes, &releaseInfo)
		if err != nil {
			return versions, err
		}

		version := OCPVersion{
			Name: requestedVersion,
		}

		blocking := []Job{}
		upgrade := []Job{}
		informing := []Job{}

		for jobName, job := range releaseInfo.Verify {
			if !strings.Contains(jobName, "metal") {
				continue
			}

			if !strings.Contains(job.ProwJob.Name, "e2e") {
				continue
			}

			jobType := "blocking"

			if job.Optional {
				jobType = "informing"
			}

			if job.Upgrade {
				jobType = "upgrade"
			}

			j := Job{
				Name:     jobName,
				ProwName: job.ProwJob.Name,
				Upgrade:  job.Upgrade,
				Optional: job.Optional,
			}

			switch jobType {
			case "blocking":
				blocking = append(blocking, j)
			case "informing":
				informing = append(informing, j)
			case "upgrade":
				upgrade = append(upgrade, j)
			}
		}

		sort.Sort(Jobs(blocking))
		sort.Sort(Jobs(informing))
		sort.Sort(Jobs(upgrade))

		version.Jobs = append(version.Jobs, blocking...)
		version.Jobs = append(version.Jobs, informing...)
		version.Jobs = append(version.Jobs, upgrade...)

		versions = append(versions, version)
	}

	return versions, nil
}

func GetTotalJobCount(ocpVersions []OCPVersion) int {
	total := 0

	for _, version := range ocpVersions {
		total += len(version.Jobs)
	}

	return total
}

func OpenInBrowser(url string) error {
	var cmd string
	var args []string

	switch runtime.GOOS {
	case "darwin":
		cmd = "open"
	default: // "linux", "freebsd", "openbsd", "netbsd"
		cmd = "xdg-open"
	}
	args = append(args, url)
	return exec.Command(cmd, args...).Start()
}

type keyMap struct {
	Up        key.Binding
	Down      key.Binding
	Left      key.Binding
	Right     key.Binding
	Open      key.Binding
	Update    key.Binding
	UpdateAll key.Binding
	Help      key.Binding
	Quit      key.Binding
}

func (k keyMap) ShortHelp() []key.Binding {
	return []key.Binding{k.Help, k.Quit}
}

// FullHelp returns keybindings for the expanded help view. It's part of the
// key.Map interface.
func (k keyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{
		{k.Up, k.Down, k.Left, k.Right}, // first column
		{k.Open, k.Update, k.UpdateAll}, // second column
		{k.Help, k.Quit},                // third column
	}
}

var keys = keyMap{
	Up: key.NewBinding(
		key.WithKeys("up", "k"),
		key.WithHelp("↑/k", "move up"),
	),
	Down: key.NewBinding(
		key.WithKeys("down", "j"),
		key.WithHelp("↓/j", "move down"),
	),
	Left: key.NewBinding(
		key.WithKeys("left", "h"),
		key.WithHelp("←/h", "move left"),
	),
	Right: key.NewBinding(
		key.WithKeys("right", "l"),
		key.WithHelp("→/l", "move right"),
	),
	Open: key.NewBinding(
		key.WithKeys("o"),
		key.WithHelp("o", "open in browser"),
	),
	Update: key.NewBinding(
		key.WithKeys("u"),
		key.WithHelp("u", "update"),
	),
	UpdateAll: key.NewBinding(
		key.WithKeys("U"),
		key.WithHelp("U", "update all"),
	),
	Help: key.NewBinding(
		key.WithKeys("?"),
		key.WithHelp("?", "toggle help"),
	),
	Quit: key.NewBinding(
		key.WithKeys("q", "esc", "ctrl+c"),
		key.WithHelp("q", "quit"),
	),
}

type model struct {
	cachePath            string
	err                  error
	versions             []OCPVersion
	selectedVersion      int
	selectedJob          int
	isLoadingInitialData bool
	initialProgress      progress.Model
	sub                  chan float64
	requestedVersions    []string
	releaseRepoPath      string
	width                int
	height               int
	lastUpdated          time.Time
	keys                 keyMap
	help                 help.Model
	helpVisible          bool
	fetchProgress        progress.Model
	fetching             bool
}

func (m model) Init() tea.Cmd {
	logger.Println("init")
	if m.versions == nil {
		return tea.Batch(
			startFetch(m.releaseRepoPath, m.cachePath, m.requestedVersions, m.sub),
			waitForFetch(m.sub),
		)
	}
	return nil
}

type errorMessage error

type fetchSuccessMessage struct {
	versions []OCPVersion
}

type fetchTick float64

func startFetch(releaseRepoPath string, cacheFilename string, requestedVersions []string, sub chan float64) tea.Cmd {
	return func() tea.Msg {
		versions, err := fetchInitialData(releaseRepoPath, cacheFilename, requestedVersions, sub)
		if err != nil {
			return err
		}
		return fetchSuccessMessage{
			versions: versions,
		}
	}
}

func startRefreshJob(versions []OCPVersion, versionIndex int, jobIndex int, sub chan float64) tea.Cmd {
	return func() tea.Msg {
		versions, err := refreshJob(versions, versionIndex, jobIndex, sub)
		if err != nil {
			return err
		}
		return fetchSuccessMessage{
			versions: versions,
		}
	}
}

func startRefreshAllJobs(versions []OCPVersion, sub chan float64) tea.Cmd {
	return func() tea.Msg {
		versions, err := refreshAllJobs(versions, sub)
		if err != nil {
			return err
		}
		return fetchSuccessMessage{
			versions: versions,
		}
	}
}

func waitForFetch(sub chan float64) tea.Cmd {
	return func() tea.Msg {
		p, ok := <-sub
		if ok {
			return fetchTick(p)
		}

		return nil
	}
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case errorMessage:
		logger.Println("error:", msg)
		m.err = msg
		return m, tea.Quit
	case fetchTick:
		if m.isLoadingInitialData {
			if m.initialProgress.Percent() == 1.0 {
				return m, nil
			}
			cmd := m.initialProgress.IncrPercent(float64(msg))
			return m, tea.Batch(waitForFetch(m.sub), cmd)
		}

		if m.fetching {
			if m.fetchProgress.Percent() == 1.0 {
				return m, nil
			}
			cmd := m.fetchProgress.IncrPercent(float64(msg))
			return m, tea.Batch(waitForFetch(m.sub), cmd)
		}

	case fetchSuccessMessage:
		m.versions = msg.versions
		m.isLoadingInitialData = false
		m.fetching = false
		m.lastUpdated = time.Now()

		err := Serialize(Cache{
			OCPVersions: m.versions,
			LastUpdated: m.lastUpdated,
		}, m.cachePath)

		if err != nil {
			m.err = fmt.Errorf("failed to serialize data: %w", err)
		}

		return m, nil
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
	case tea.KeyMsg:
		switch {
		case key.Matches(msg, m.keys.Quit):
			return m, tea.Quit
		case key.Matches(msg, m.keys.Up):
			m.selectedJob--
			if m.selectedJob < 0 {
				m.selectedJob = 0
			}
		case key.Matches(msg, m.keys.Down):
			m.selectedJob++
			if m.selectedJob > len(m.versions[m.selectedVersion].Jobs)-1 {
				m.selectedJob = len(m.versions[m.selectedVersion].Jobs) - 1
			}
		case key.Matches(msg, m.keys.Right):
			m.selectedVersion++
			if m.selectedVersion > len(m.versions)-1 {
				m.selectedVersion = len(m.versions) - 1
			}
		case key.Matches(msg, m.keys.Left):
			m.selectedVersion--
			if m.selectedVersion < 0 {
				m.selectedVersion = 0
			}
		case key.Matches(msg, m.keys.Open):
			job := m.versions[m.selectedVersion].Jobs[m.selectedJob]
			OpenInBrowser(job.HistoryLink())
		case key.Matches(msg, m.keys.Update):
			m.sub = make(chan float64, 10)
			m.fetching = true
			m.fetchProgress = newProgress()
			return m, tea.Batch(
				startRefreshJob(m.versions, m.selectedVersion, m.selectedJob, m.sub),
				waitForFetch(m.sub),
			)
		case key.Matches(msg, m.keys.UpdateAll):
			m.sub = make(chan float64, 10)
			m.fetching = true
			m.fetchProgress = newProgress()
			return m, tea.Batch(
				startRefreshAllJobs(m.versions, m.sub),
				waitForFetch(m.sub),
			)
		case key.Matches(msg, m.keys.Help):
			m.helpVisible = !m.helpVisible
		}
	case progress.FrameMsg:
		if m.isLoadingInitialData {
			progressModel, cmd := m.initialProgress.Update(msg)
			m.initialProgress = progressModel.(progress.Model)
			return m, cmd
		}

		if m.fetching {
			progressModel, cmd := m.fetchProgress.Update(msg)
			m.fetchProgress = progressModel.(progress.Model)
			return m, cmd
		}

		return m, nil
	}

	return m, nil
}

func (m model) View() string {
	if m.isLoadingInitialData {
		s := "Loading data, please wait...\n"
		s += m.initialProgress.View()
		return lipgloss.NewStyle().Align(lipgloss.Center, lipgloss.Center).Width(m.width).Height(m.height - 2).Render(s)
	}

	if m.helpVisible {
		return m.help.FullHelpView(m.keys.FullHelp())
	}

	blocks := []string{}

	for i, version := range m.versions {
		b := ""

		if m.selectedVersion == i {
			b += versionStyleSelected.Render(version.Name)
		} else {
			b += versionStyle.Render(version.Name)
		}

		for index, job := range version.Jobs {
			b += "\n"

			jobName := job.Name

			if strings.HasPrefix(jobName, "metal-ipi-") {
				jobName = strings.Replace(jobName, "metal-ipi-", "", 1)
			}

			if strings.HasPrefix(jobName, "metal-") {
				jobName = strings.Replace(jobName, "metal-", "", 1)
			}

			jobType := "b"

			if job.Optional {
				jobType = "i"
			}

			if job.Upgrade {
				jobType = "u"
			}

			b += jobTypeStyle.Render(jobType)
			b += " "

			if i == m.selectedVersion && index == m.selectedJob {
				b += jobStyleSelected.Render(jobName)
			} else {
				b += jobName
			}

			b += "\n"
			b += "  "

			builds := job.Builds

			if len(builds) > BUILDS_PER_JOB {
				builds = builds[:BUILDS_PER_JOB]
			}

			for _, build := range builds {
				if build.Passed {
					b += green.Render(" ")
				} else {
					b += red.Render(" ")
				}
			}

			b += "\n"

		}

		if i == m.selectedVersion {
			b = selectedBorder.Render(b)
		} else {
			b = border.Render(b)
		}
		blocks = append(blocks, b)

	}

	content := lipgloss.JoinHorizontal(lipgloss.Top, blocks...)
	content += fmt.Sprintf("\n\nPress ? for help.  Last updated: %s", m.lastUpdated.Format("2006-01-02 15:04:05"))

	if m.fetching {
		content += "\n\n"
		content += m.fetchProgress.View()
		content += " Loading..."
	}

	return content
}

func newProgress() progress.Model {
	return progress.New(progress.WithSolidFill("#3f3f46"))
}

func refreshJob(versions []OCPVersion, versionIndex int, jobIndex int, sub chan float64) ([]OCPVersion, error) {
	version := versions[versionIndex]
	job := version.Jobs[jobIndex]

	builds := []Build{}
	var err error

	if len(job.Builds) == 0 {
		builds, err = GetAllBuilds(job)
	} else {
		builds, err = GetBuildsSince(job, job.Builds[0].ID)
	}

	if err != nil {
		return nil, err
	}

	version.Jobs[jobIndex].Builds = append(version.Jobs[jobIndex].Builds, builds...)

	sort.Slice(version.Jobs[jobIndex].Builds, func(a, b int) bool {
		return version.Jobs[jobIndex].Builds[a].ID > version.Jobs[jobIndex].Builds[b].ID
	})

	versions[versionIndex] = version

	// Fake progress
	for i := 0; i < 5; i++ {
		sub <- float64(i) * 0.2
		time.Sleep(time.Millisecond * 150)
	}

	sub <- 1.0

	close(sub)

	return versions, nil
}

func refreshAllJobs(versions []OCPVersion, sub chan float64) ([]OCPVersion, error) {
	total := GetTotalJobCount(versions)
	step := (100.0 / float64(total)) / 100.0

	for _, version := range versions {
		for jobIndex, job := range version.Jobs {
			job := Job{Name: job.ProwName}

			builds, err := GetBuildsSince(job, job.Builds[0].ID)

			if err != nil {
				return nil, err
			}

			version.Jobs[jobIndex].Builds = append(version.Jobs[jobIndex].Builds, builds...)

			sort.Slice(version.Jobs[jobIndex].Builds, func(a, b int) bool {
				return version.Jobs[jobIndex].Builds[a].ID > version.Jobs[jobIndex].Builds[b].ID
			})

			sub <- step

		}
	}

	close(sub)

	return versions, nil
}

func fetchInitialData(releaseRepoPath string, cacheFilename string, requestedVersions []string, sub chan float64) ([]OCPVersion, error) {
	cache, found, err := Deserialize(cacheFilename)
	if err != nil {
		return nil, err
	}

	if found {
		return cache.OCPVersions, nil
	}

	ocpVersions, err := LoadOCPVersionConfig(releaseRepoPath, requestedVersions)
	if err != nil {
		return nil, err
	}

	total := GetTotalJobCount(ocpVersions) * BUILDS_PER_JOB
	step := (100.0 / float64(total)) / 100.0

	for _, version := range ocpVersions {
		for jobIndex, job := range version.Jobs {
			if !strings.Contains(job.Name, "metal") {
				continue
			}

			j := Job{Name: job.ProwName}

			buildIds, err := FetchAllBuildIds(j)
			if err != nil {
				return nil, err
			}

			builds := []Build{}

			for i, id := range buildIds {
				if i >= BUILDS_PER_JOB {
					break
				}

				b, err := GetBuild(id, job)
				if err != nil {
					return ocpVersions, err
				}

				sub <- step

				if !b.IsFinished() {
					continue
				}

				builds = append(builds, b)
			}

			version.Jobs[jobIndex].Builds = builds
		}
	}

	close(sub)

	return ocpVersions, nil
}

func Serialize(c Cache, filename string) error {
	f, err := os.Create(filename)
	if err != nil {
		return err
	}
	defer f.Close()

	buffer, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}

	_, err = f.Write(buffer)
	if err != nil {
		return err
	}
	return nil
}

func Deserialize(filename string) (Cache, bool, error) {
	var c Cache

	if _, err := os.Stat(filename); errors.Is(err, os.ErrNotExist) {
		return c, false, nil
	}

	logger.Println("Cache file found, loading data")

	buffer, err := os.ReadFile(filename)
	if err != nil {
		return c, false, err
	}

	err = json.Unmarshal(buffer, &c)

	if err != nil {
		return c, false, err
	}

	return c, true, nil
}

func Run(releaseRepoPath string, requestedVersions []string) (err error) {
	cacheFilename, err := xdg.CacheFile("metal-wall.json")

	if err != nil {
		return fmt.Errorf("unable to determine cache file location: %w", err)
	}

	m := model{
		cachePath:            cacheFilename,
		releaseRepoPath:      releaseRepoPath,
		requestedVersions:    requestedVersions,
		isLoadingInitialData: true,
		sub:                  make(chan float64, 10),
		initialProgress:      newProgress(),
		help:                 help.New(),
		keys:                 keys,
		fetching:             false,
		fetchProgress:        newProgress(),
	}

	res, err := tea.NewProgram(m, tea.WithAltScreen()).Run()

	if err != nil {
		fmt.Printf("error: %v\n", err)
		return err
	}

	// If the tui program exits with an error, show the error log
	t := res.(model)

	if t.err != nil {
		fmt.Println(logBuffer.String())
	}

	return nil
}

// CLI flags
var Versions string
var Since string
var ReleaseRepoPath string

var rootCmd = &cobra.Command{
	Use:   "metal-support",
	Short: "A tool for monitoring/troubleshooting metal-ipi OpenShift CI releases",
	RunE: func(cmd *cobra.Command, args []string) error {
		if _, err := os.Stat(ReleaseRepoPath); os.IsNotExist(err) {
			return fmt.Errorf("release repository path does not exist: %s", ReleaseRepoPath)
		}
		requestedVersions := strings.Split(Versions, ",")
		return Run(ReleaseRepoPath, requestedVersions)

	},
}

func main() {
	rootCmd.PersistentFlags().StringVar(&Versions, "versions", "4.19,4.18,4.17,4.16,4.15,4.14,4.13,4.12", "OpenShift release versions to be analyzed (comma separated)")
	rootCmd.PersistentFlags().StringVar(&ReleaseRepoPath, "release-repo-path", "release", "")

	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
