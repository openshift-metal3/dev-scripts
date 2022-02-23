package main

import (
	"fmt"
	"log"
	"os"
	"time"

	"github.com/openshift-metal3/dev-scripts/metal-releases/pkg/commands"
	"github.com/urfave/cli/v2"
)

func main() {

	app := &cli.App{
		Name:                 "metal-support",
		Usage:                "",
		UsageText:            "",
		Description:          "A tool for monitoring/troubleshooting metal-ipi OpenShift CI releases",
		EnableBashCompletion: true,

		Commands: []*cli.Command{
			{
				Name:    "check",
				Aliases: []string{"ch"},
				Usage:   "Scans latest release jobs for intermittent e2e test failures",
				Flags: []cli.Flag{
					&cli.StringFlag{
						Name:    "versions",
						Aliases: []string{"v"},
						Value:   "4.10",
						Usage:   "OpenShift release versions to be analized (comma separated)",
					},
					&cli.StringFlag{
						Name:    "since",
						Aliases: []string{"s"},
						Value:   fmt.Sprintf("%d-%02d-%02d", time.Now().Year(), time.Now().Month(), time.Now().Day()),
					},
				},
				Action: func(c *cli.Context) error {
					return commands.NewCheckCommand(c.String("versions"), c.String("since")).Run()
				},
			},
			{
				Name:    "metal-wall",
				Aliases: []string{"mw"},
				Usage:   "Starts a local web server to monitor all the metal jobs",
				Flags: []cli.Flag{
					&cli.StringFlag{
						Name:    "port",
						Aliases: []string{"p"},
						Value:   "8081",
					},
					&cli.StringFlag{
						Name:    "versions",
						Aliases: []string{"v"},
						Value:   "4.11,4.10,4.9,4.8,4.7",
						Usage:   "OpenShift release versions to be analized (comma separated)",
					},
					&cli.BoolFlag{
						Name:    "cache",
						Aliases: []string{"c"},
						Value:   true,
						Usage:   "Use cached data to speed up the bootstrap",
					},
				},
				Action: func(c *cli.Context) error {
					return commands.NewMetalWallCommand(c.String("port"), c.String("versions"), c.Bool("cache")).Run()
				},
			},
		},
	}

	err := app.Run(os.Args)
	if err != nil {
		log.Fatal(err)
	}
}
