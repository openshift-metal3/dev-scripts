package commands

import (
	"bytes"
	"embed"
	"encoding/gob"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/hashicorp/go-version"
	"github.com/openshift-metal3/dev-scripts/metal-releases/pkg/jobs"
)

//go:embed build/*
var reactFiles embed.FS
var cacheFilename = ".metal-wall-cache"

type MetalWallCommand struct {
	port        string
	versions    []string
	useCache    bool
	builds      map[string]*jobs.Build // build id -> build
	BuildsInfo  map[string][]BuildInfo // version -> info
	LastUpdated time.Time

	mu sync.Mutex
}

type BuildInfo struct {
	Version            string `json:"version"`
	JobName            string `json:"job_name"`
	BuildId            string `json:"build_id"`
	Passed             bool   `json:"passed"`
	NewBuildInProgress bool   `json:"new_build_in_progress"`
	Url                string `json:"url"`
	Type               string `json:"type"`
	Finished           string `json:"finished"`
	FailureReason      string `json:"failure_reason"`
}

type Version struct {
	Name   string      `json:"name"`
	Builds []BuildInfo `json:"builds"`
}

type JSONResponse struct {
	Versions    []Version `json:"versions"`
	LastUpdated time.Time `json:"last_updated"`
}

func NewMetalWallCommand(port string, versions string, useCache bool) Command {
	return &MetalWallCommand{
		port:     port,
		versions: strings.Split(versions, ","),
		useCache: useCache,

		builds:     make(map[string]*jobs.Build),
		BuildsInfo: make(map[string][]BuildInfo),
	}
}

func (mw *MetalWallCommand) AsJSON() JSONResponse {

	defer mw.mu.Unlock()
	mw.mu.Lock()

	versions := []Version{}
	for version, builds := range mw.BuildsInfo {
		versions = append(versions, Version{Name: version, Builds: builds})
	}
	sort.SliceStable(versions, func(i, j int) bool {
		v1, _ := version.NewVersion(versions[i].Name)
		v2, _ := version.NewVersion(versions[j].Name)
		return v1.GreaterThan(v2)
	})
	return JSONResponse{Versions: versions, LastUpdated: mw.LastUpdated}
}

func (mw *MetalWallCommand) Run() (err error) {

	var cacheFound bool
	if mw.useCache {
		cacheFound, err = mw.deserialize()
		if err != nil {
			return err
		}
	}

	if !cacheFound {
		log.Println("Warming up, it could take a while...")
		mw.fetchInitialData()
	}
	mw.setupBackgroundUpdate()

	log.Println("Launching metal wall server at port", mw.port)
	var reactFS = http.FS(reactFiles)
	fs := rootPath(http.FileServer(reactFS))
	http.Handle("/", fs)

	http.HandleFunc("/data.json", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(mw.AsJSON())
	})
	log.Fatal(http.ListenAndServe(fmt.Sprintf(":%s", mw.port), nil))

	return nil
}

func (mw *MetalWallCommand) setupBackgroundUpdate() {
	ticker := time.NewTicker(30 * time.Second)
	go func() {
		for {
			<-ticker.C
			mw.refreshData()
		}
	}()
}

func rootPath(h http.Handler) http.Handler {
	staticDir := "build"
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" {
			r.URL.Path = fmt.Sprintf("/%s/", staticDir)
		} else {
			b := strings.Split(r.URL.Path, "/")[0]
			if b != staticDir {
				r.URL.Path = fmt.Sprintf("/%s%s", staticDir, r.URL.Path)
			}
		}
		h.ServeHTTP(w, r)
	})
}

func (mw *MetalWallCommand) refreshData() {

	defer mw.mu.Unlock()
	mw.mu.Lock()

	start := time.Now()

	defer func() {
		end := time.Now()
		log.Printf("Refresh data completed in %0.2f seconds\n", end.Sub(start).Seconds())
	}()

	for v, infos := range mw.BuildsInfo {
		for i, info := range infos {
			b := mw.builds[info.BuildId]

			latest, err := b.Job().GetLatestBuild()
			if err != nil {
				log.Printf("Unable to get latest build for %s (%s). Error: %s\n", info.JobName, info.BuildId, err)
				continue
			}
			// Check if there's a new build for the job
			if b.Id() != latest.Id() {
				err = latest.LoadCurrentStatus()
				if err != nil {
					log.Printf("Unable to get latest build info for %s (%s). Error: %s\n", info.JobName, info.BuildId, err)
					continue
				}

				// Update view
				if !latest.IsFinished() {
					log.Printf("Found new build for job %s (%s) in progress\n", b.Job().Name(), latest.Id())
					info.NewBuildInProgress = true
				} else {
					log.Printf("Found new completed build for job %s (%s) ", b.Job().Name(), latest.Id())
					// Update builds map
					delete(mw.builds, info.BuildId)
					mw.builds[latest.Id()] = latest

					info.NewBuildInProgress = false
					info.BuildId = latest.Id()
					info.Passed = latest.Passed()
					info.Url = latest.Url()
					info.Finished = latest.Finished().String()
					info.FailureReason = ""

					// If current build failed, try to detect the reason
					if !info.Passed {
						info.FailureReason, err = latest.GetFailureReason()
						if err != nil {
							log.Printf("Unable to detect failure reason for build %s. Error: %s\n", latest.Id(), err)
						} else {
							info.Url = fmt.Sprintf("%s/%s", latest.ArtifactsUrl(), info.FailureReason)
						}
					}
				}
				mw.BuildsInfo[v][i] = info
			}
		}
	}
	mw.LastUpdated = time.Now().UTC()

	mw.serialize()
}

func (mw *MetalWallCommand) fetchJobs(getJobs func(version string) ([]*jobs.Job, error), jobType string) error {

	for _, v := range mw.versions {
		var infos []BuildInfo

		allJobs, err := getJobs(v)
		if err != nil {
			return err
		}

		log.Printf("  [%s]\n", v)
		for _, j := range allJobs {

			buildIds, err := j.FetchAllBuildIds()
			if err != nil {
				return err
			}

			for _, id := range buildIds {
				b := jobs.NewBuild(id, j)
				b.LoadCurrentStatus()

				if !b.IsFinished() {
					continue
				}

				mw.builds[b.Id()] = b
				log.Printf("    %-110s%s\n", j.Name(), b.Id())

				info := BuildInfo{
					Version:  v,
					JobName:  j.DisplayName(),
					BuildId:  b.Id(),
					Url:      b.Url(),
					Passed:   b.Passed(),
					Type:     jobType,
					Finished: b.Finished().String(),
				}

				if !info.Passed {
					info.FailureReason, err = b.GetFailureReason()
					if err != nil {
						log.Printf("Unable to detect failure reason for build %s. Error: %s\n", b.Id(), err)
					} else {
						info.Url = fmt.Sprintf("%s/%s", b.ArtifactsUrl(), info.FailureReason)
					}
				}

				infos = append(infos, info)

				break
			}
		}
		mw.BuildsInfo[v] = append(mw.BuildsInfo[v], infos...)
	}

	return nil
}

// Gets the current latest completed build
func (mw *MetalWallCommand) fetchInitialData() error {

	allJobs := map[string]func(version string) (jobs []*jobs.Job, err error){
		"blocking":  jobs.BlockingJobs,
		"informing": jobs.InformingJobs,
		"upgrade":   jobs.UpgradeJobs,
	}

	for jobType, getter := range allJobs {
		log.Println()
		log.Printf("[%s]\n", jobType)
		if err := mw.fetchJobs(getter, jobType); err != nil {
			return err
		}
	}

	mw.LastUpdated = time.Now().UTC()
	if err := mw.serialize(); err != nil {
		return err
	}

	return nil
}

func (mw *MetalWallCommand) GobEncode() ([]byte, error) {
	buf := new(bytes.Buffer)
	encoder := gob.NewEncoder(buf)
	err := encoder.Encode(mw.builds)
	if err != nil {
		return nil, err
	}
	err = encoder.Encode(mw.BuildsInfo)
	if err != nil {
		return nil, err
	}
	err = encoder.Encode(mw.LastUpdated)
	if err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func (mw *MetalWallCommand) GobDecode(buf []byte) error {
	decoder := gob.NewDecoder(bytes.NewBuffer(buf))
	err := decoder.Decode(&mw.builds)
	if err != nil {
		return err
	}
	err = decoder.Decode(&mw.BuildsInfo)
	if err != nil {
		return err
	}
	err = decoder.Decode(&mw.LastUpdated)
	if err != nil {
		return err
	}
	return nil
}

func (mw *MetalWallCommand) serialize() error {

	buffer := new(bytes.Buffer)
	err := gob.NewEncoder(buffer).Encode(mw)
	if err != nil {
		return err
	}
	workingDir, err := os.Getwd()
	if err != nil {
		return err
	}
	f, err := os.Create(filepath.Join(workingDir, cacheFilename))
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = f.Write(buffer.Bytes())
	if err != nil {
		return err
	}
	return nil
}

func (mw *MetalWallCommand) deserialize() (bool, error) {

	if _, err := os.Stat(cacheFilename); errors.Is(err, os.ErrNotExist) {
		return false, nil
	}

	log.Println("Cache file found, loading data")

	buffer, err := os.ReadFile(cacheFilename)
	if err != nil {
		return false, err
	}

	d := gob.NewDecoder(bytes.NewBuffer(buffer))
	err = d.Decode(mw)
	if err != nil {
		return false, err
	}

	return true, nil
}
