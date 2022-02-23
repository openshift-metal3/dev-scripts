package jobs

import (
	"bytes"
	"encoding/gob"
	"encoding/json"
	"encoding/xml"
	"errors"
	"fmt"
	"time"
)

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
	// The job owner of this build
	job *Job
	// The unique build id
	id string
	// The starting info of the build
	started Started
	// The end status of the build
	finished *Finished
	// A link to the build
	buildUrl string
	// A link to the build steps artifacts
	artifactsUrl string
}

func (b *Build) Id() string {
	return b.id
}

func (b *Build) IsFinished() bool {
	return b.finished != nil
}

func (b *Build) Passed() bool {
	return b.finished.Passed
}

func (b *Build) Url() string {
	return b.buildUrl
}

func (b *Build) ArtifactsUrl() string {
	return b.artifactsUrl
}

func (b *Build) Finished() time.Time {
	return time.Unix(b.finished.Timestamp, 0)
}

func (b *Build) Job() *Job {
	return b.job
}

func (b *Build) getStepStatus(stepUrl string) (Finished, error) {

	var f Finished
	finished, err := FetchRemoteFile(fmt.Sprintf("%s/%s/finished.json", b.artifactsUrl, stepUrl))
	if err != nil {
		return f, err
	}

	err = json.Unmarshal(finished, &f)
	return f, err
}

func (b *Build) LoadCurrentStatus() error {

	started, err := FetchRemoteFile(fmt.Sprintf("%s/started.json", b.buildUrl))
	if err != nil {
		return err
	}
	err = json.Unmarshal(started, &b.started)
	if err != nil {
		return err
	}

	finished, err := FetchRemoteFile(fmt.Sprintf("%s/finished.json", b.buildUrl))
	if err != nil {
		return err
	}

	var f Finished
	err = json.Unmarshal(finished, &f)
	// If the build is still pending, the finished.json file is not published
	if err == nil {
		b.finished = &f
	}
	return nil
}

// Try to determine what caused the failure of the current build
func (b *Build) GetFailureReason() (string, error) {

	// There could be three main reasons for a build failure:
	// - Packet setup didn't succeed
	// - Dev-scripts setup wasn't able to correctly deploy a cluster
	// - E2e test failure

	// In a normal scenario, the most frequent cause of failure it's an e2e
	// test failure, so let's start from it
	e2eTestStep, err := b.getStepStatus("baremetalds-e2e-test")
	if err == nil && !e2eTestStep.Passed {
		return "baremetalds-e2e-test", nil
	}

	// Then check if dev-scripts failed
	dsStep, err := b.getStepStatus("baremetalds-devscripts-setup")
	if err == nil && !dsStep.Passed {
		return "baremetalds-devscripts-setup", nil
	}

	// Finally, let's check the baremetal instance
	packetSetupStep, err := b.getStepStatus("baremetalds-packet-setup")
	if err == nil && !packetSetupStep.Passed {
		return "baremetalds-packet-setup", nil
	}

	return "unknown", nil
}

// LoadTestResults fetches the test results related to the current build
func (b *Build) LoadTestResults() (*TestSuite, error) {
	testsUrl := fmt.Sprintf("%s/%s/%s/artifacts/%s/baremetalds-e2e-test/artifacts/junit/", baseArtifactsUrl, b.job.name, b.id, b.job.safeName)

	suite := TestSuite{}
	testsFilename, err := b.getTestResultsFilename(testsUrl)
	if err != nil {
		// In some cases the test step could fail before running the tests
		// so the results artifacts are not published. This build will be
		// skipped
		return &suite, nil
	}

	tests, err := FetchRemoteFile(fmt.Sprintf("%s/%s", testsUrl, testsFilename))
	if err != nil {
		return nil, err
	}
	err = xml.Unmarshal(tests, &suite)
	if err != nil {
		return nil, err
	}

	return &suite, nil
}

func (b *Build) getTestResultsFilename(url string) (string, error) {
	s := NewHtmlScraper(url, `.*/(junit_e2e.*\.xml)`)
	res, err := s.Get()
	if err != nil {
		return "", err
	}

	if len(res) == 0 {
		return "", errors.New("not found")
	}

	return res[0], nil
}

func (b *Build) GobEncode() ([]byte, error) {
	buf := new(bytes.Buffer)
	encoder := gob.NewEncoder(buf)
	err := encoder.Encode(b.artifactsUrl)
	if err != nil {
		return nil, err
	}
	err = encoder.Encode(b.buildUrl)
	if err != nil {
		return nil, err
	}
	err = encoder.Encode(b.finished)
	if err != nil {
		return nil, err
	}
	err = encoder.Encode(b.id)
	if err != nil {
		return nil, err
	}
	err = encoder.Encode(b.job)
	if err != nil {
		return nil, err
	}
	err = encoder.Encode(b.started)
	if err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func (b *Build) GobDecode(buf []byte) error {
	decoder := gob.NewDecoder(bytes.NewBuffer(buf))

	err := decoder.Decode(&b.artifactsUrl)
	if err != nil {
		return err
	}
	err = decoder.Decode(&b.buildUrl)
	if err != nil {
		return err
	}

	var finished Finished
	err = decoder.Decode(&finished)
	if err != nil {
		return err
	}
	b.finished = &finished

	err = decoder.Decode(&b.id)
	if err != nil {
		return err
	}

	var job Job
	err = decoder.Decode(&job)
	if err != nil {
		return err
	}
	b.job = &job

	err = decoder.Decode(&b.started)
	if err != nil {
		return err
	}
	return nil
}

func NewBuild(id string, job *Job) *Build {
	return &Build{
		id:           id,
		job:          job,
		buildUrl:     fmt.Sprintf("%s/%s/%s", baseArtifactsUrl, job.name, id),
		artifactsUrl: fmt.Sprintf("%s/%s/%s/artifacts/%s", baseArtifactsUrl, job.name, id, job.safeName),
	}
}
