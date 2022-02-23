package commands

import (
	"log"
	"strings"
	"time"

	"github.com/openshift-metal3/dev-scripts/metal-releases/pkg/jobs"
)

type CheckCommand struct {
	versions []string
	since    string
}

var ()

func NewCheckCommand(versions string, since string) Command {
	return CheckCommand{
		versions: strings.Split(versions, ","),
		since:    since,
	}
}

func (c CheckCommand) Run() error {

	start := time.Now()

	defer func() {
		end := time.Now()
		log.Printf("Check command completed in %0.2f seconds\n", end.Sub(start).Seconds())
	}()

	for _, v := range c.versions {
		blockingJobs, err := jobs.BlockingJobs(v)
		if err != nil {
			return err
		}

		for _, j := range blockingJobs {
			err := j.GetBuildsSince(c.since)
			if err != nil {
				return err
			}

			err = j.LookForIntermittentFailures()
			if err != nil {
				return err
			}

			j.ShowIntermittentFailures()
		}
	}
	return nil
}
