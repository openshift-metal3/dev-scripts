package jobs

import (
	"bytes"
	"encoding/gob"
	"errors"
	"fmt"
	"log"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/hashicorp/go-version"
)

const (
	// This is the url where the Prow jobs artifacts are stored
	baseArtifactsUrl = "https://gcsweb-ci.apps.ci.l2s4.p1.openshiftapps.com/gcs/origin-ci-test/logs"

	// Max number of stored builds per job
	maxBuilds = 20
)

// For the sake of simplicity, let's use hard-coded lists
var (
	blockingJobs []string = []string{
		"periodic-ci-openshift-release-master-nightly-%s-e2e-metal-ipi",
		"periodic-ci-openshift-release-master-nightly-%s-e2e-metal-ipi-ovn-ipv6",
		"periodic-ci-openshift-release-master-nightly-%s-e2e-metal-ipi-serial-ipv4",
	}
	informingJobs []string = []string{
		"periodic-ci-openshift-release-master-nightly-%s-e2e-metal-ipi-virtualmedia",
		"periodic-ci-openshift-release-master-nightly-%s-e2e-metal-ipi-compact",
		"periodic-ci-openshift-release-master-nightly-%s-e2e-metal-ipi-ovn-dualstack",
		"periodic-ci-openshift-release-master-nightly-%s-e2e-metal-ipi-serial-ovn-ipv6",
		"periodic-ci-openshift-release-master-nightly-%s-e2e-metal-ipi-serial-virtualmedia",
		"periodic-ci-openshift-release-master-nightly-%s-e2e-metal-ipi-serial-compact",
		"periodic-ci-openshift-release-master-nightly-%s-e2e-metal-ipi-serial-ovn-dualstack",
	}
	upgradeJobs []string = []string{
		"periodic-ci-openshift-release-master-nightly-%s-e2e-metal-ipi-upgrade",
		"periodic-ci-openshift-release-master-nightly-%s-e2e-metal-ipi-upgrade-ovn-ipv6",
	}
	upgradeStableJobs []string = []string{
		"periodic-ci-openshift-release-master-nightly-%s-upgrade-from-stable-%s-e2e-metal-ipi-upgrade",
		"periodic-ci-openshift-release-master-nightly-%s-upgrade-from-stable-%s-e2e-metal-ipi-upgrade-ovn-ipv6",
	}
)

// BlockingJobs returns a list of blocking jobs for the specified version
func BlockingJobs(version string) ([]*Job, error) {
	return makeJobs(version, blockingJobs)
}

// InformingJobs returns a list of informing jobs for the specified version (upgrades excluded)
func InformingJobs(version string) ([]*Job, error) {
	return makeJobs(version, informingJobs)
}

// UpgradeJobs returns a list of composed by upgrade and stable upgrade jobs for the specified version
func UpgradeJobs(v string) ([]*Job, error) {
	jobs, err := makeJobs(v, upgradeJobs)
	if err != nil {
		return nil, err
	}

	// Get previous minor version
	currV, err := version.NewVersion(v)
	if err != nil {
		return nil, err
	}

	prevMajor := currV.Segments()[0]
	prevMinor := currV.Segments()[1] - 1
	if prevMinor < 0 {
		return nil, errors.New("major version switch not supported")
	}

	prevV, err := version.NewVersion(fmt.Sprintf("%d.%d", prevMajor, prevMinor))
	if err != nil {
		return nil, err
	}
	for _, j := range upgradeStableJobs {
		jobs = append(jobs, NewJob(fmt.Sprintf(j, v, prevV.Original()), v))
	}

	return jobs, nil
}

func makeJobs(version string, jobsTemplate []string) (jobs []*Job, err error) {
	for _, j := range jobsTemplate {
		jobs = append(jobs, NewJob(fmt.Sprintf(j, version), version))
	}
	return jobs, nil
}

func getDisplayName(name string) string {
	prefix := "e2e-metal-ipi-"

	idx := strings.Index(name, prefix)
	if idx < 0 {
		return "ipv4"
	}

	displayName := name[idx+len(prefix):]
	displayName = strings.ReplaceAll(displayName, "-", " ")

	if displayName == "" {
		displayName = "ipv4"
	}

	re := regexp.MustCompile(`.*upgrade-from-stable-(\d+.\d+)-e2e-metal-ipi`)
	if matches := re.FindStringSubmatch(name); matches != nil {
		displayName = fmt.Sprintf("%s (from %s)", displayName, matches[1])
	}
	return displayName
}

// NewJob creates a new job instance
func NewJob(name, version string) *Job {

	safeName := name[strings.Index(name, "e2e"):]
	displayName := getDisplayName(name)
	url := fmt.Sprintf("%s/%s/", baseArtifactsUrl, name)

	return &Job{
		name:        name,
		safeName:    safeName,
		displayName: displayName,
		version:     version,
		url:         url,
		builds:      []*Build{},
		history: JobHistory{
			Data: make(map[string]TestHistory),
		},
	}
}

// TestHistory is used to accumulate the detected flakes for given test
type TestHistory struct {
	PreviousState bool
	Flakes        float32
}

// JobHistory keeps all the relevant info for the analyzed builds
// for a given job
type JobHistory struct {
	From        int64
	To          int64
	TotalBuilds float32
	Data        map[string]TestHistory
}

// Job represent a Prow job
type Job struct {
	name        string
	safeName    string
	displayName string
	version     string
	url         string
	builds      []*Build
	history     JobHistory
}

func (j *Job) GobEncode() ([]byte, error) {
	buf := new(bytes.Buffer)
	encoder := gob.NewEncoder(buf)
	err := encoder.Encode(j.name)
	if err != nil {
		return nil, err
	}
	err = encoder.Encode(j.safeName)
	if err != nil {
		return nil, err
	}
	err = encoder.Encode(j.displayName)
	if err != nil {
		return nil, err
	}
	err = encoder.Encode(j.version)
	if err != nil {
		return nil, err
	}
	err = encoder.Encode(j.url)
	if err != nil {
		return nil, err
	}
	// err = encoder.Encode(j.builds)
	// if err != nil {
	// 	return nil, err
	// }
	// err = encoder.Encode(j.history)
	// if err != nil {
	// 	return nil, err
	// }
	return buf.Bytes(), nil
}

func (j *Job) GobDecode(buf []byte) error {
	decoder := gob.NewDecoder(bytes.NewBuffer(buf))
	err := decoder.Decode(&j.name)
	if err != nil {
		return err
	}
	err = decoder.Decode(&j.safeName)
	if err != nil {
		return err
	}
	err = decoder.Decode(&j.displayName)
	if err != nil {
		return err
	}
	err = decoder.Decode(&j.version)
	if err != nil {
		return err
	}
	err = decoder.Decode(&j.url)
	if err != nil {
		return err
	}
	// err = decoder.Decode(&j.builds)
	// if err != nil {
	// 	return err
	// }
	// err = decoder.Decode(&j.history)
	// if err != nil {
	// 	return err
	// }
	return nil
}

func (j *Job) Name() string {
	return j.name
}

func (j *Job) SafeName() string {
	return j.safeName
}

func (j *Job) DisplayName() string {
	return j.displayName
}

func (j *Job) FetchAllBuildIds() (buildIds []string, err error) {
	s := NewHtmlScraper(j.url, `.*/(\d+)/`)
	buildIds, err = s.Get()
	if err != nil {
		return nil, err
	}

	sort.Slice(buildIds, func(i, j int) bool {
		return buildIds[i] > buildIds[j]
	})
	return buildIds, nil
}

func (j *Job) GetLatestBuild() (*Build, error) {
	latest, err := FetchRemoteFile(fmt.Sprintf("%s/latest-build.txt", j.url))
	if err != nil {
		return nil, err
	}

	return NewBuild(string(latest), j), nil
}

func (j *Job) GetBuildsSince(from string) error {
	log.Println("--------------------------------------------------")
	log.Println(j.name, "Listing builds")
	since, err := time.Parse(time.RFC3339, fmt.Sprintf("%sT00:00:00Z", from))
	if err != nil {
		return err
	}

	buildIds, err := j.FetchAllBuildIds()
	if err != nil {
		return err
	}

	for _, id := range buildIds {
		b := NewBuild(id, j)
		b.LoadCurrentStatus()

		if !b.IsFinished() {
			continue
		}

		if b.Finished().Before(since) {
			break
		}

		j.builds = append(j.builds, b)

		if len(j.builds) >= maxBuilds {
			break
		}

	}

	log.Println(j.name, fmt.Sprintf("Found %d builds since %s", len(j.builds), from))
	return nil
}

func (j *Job) LookForIntermittentFailures() error {
	for _, b := range j.builds {
		suite, err := b.LoadTestResults()
		if err != nil {
			return err
		}

		for _, tc := range suite.TestCases {

			if tc.Ignore() {
				continue
			}

			thc, ok := j.history.Data[tc.Name]
			if !ok {
				thc = TestHistory{
					PreviousState: true,
				}
			}

			if tc.IsPassed() != thc.PreviousState {
				thc.Flakes += 0.5
			}
			thc.PreviousState = tc.IsPassed()

			j.history.Data[tc.Name] = thc
		}

		if len(suite.TestCases) > 0 {
			j.history.TotalBuilds += 1.0
		}
	}

	j.history.To = j.builds[0].finished.Timestamp
	j.history.From = j.builds[len(j.builds)-1].finished.Timestamp

	return nil
}

func (j *Job) ShowIntermittentFailures() {

	type FlakyTest struct {
		name      string
		flakiness float32
	}

	flakes := []FlakyTest{}
	for k, v := range j.history.Data {
		if v.Flakes == 0.0 {
			continue
		}

		flakiness := v.Flakes / j.history.TotalBuilds
		flakes = append(flakes, FlakyTest{
			name:      k,
			flakiness: flakiness,
		})
	}

	sort.Slice(flakes, func(i, j int) bool {
		return flakes[i].flakiness > flakes[j].flakiness
	})

	to := time.Unix(j.history.To, 0).UTC()
	from := time.Unix(j.history.From, 0).UTC()
	log.Println(j.name, fmt.Sprintf("Top flaky tests (last %0.f days, %0.f builds)", to.Sub(from).Hours()/24, j.history.TotalBuilds))
	for _, f := range flakes {
		log.Printf("%0.2f\t%s\n", f.flakiness, f.name)
	}
}
