package main

import (
	"encoding/base64"
	"flag"
	"fmt"
	"os"
	"strings"
	"text/template"
)

var templateBody = `---
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Name }}-bmc-secret
type: Opaque
data:
  username: {{ .EncodedUsername }}
  password: {{ .EncodedPassword }}

---
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: {{ .Name }}
spec:
  online: true
  bmc:
    address: {{ .BMCAddress }}
    credentialsName: {{ .Name }}-bmc-secret
{{- if .MAC }}
  bootMACAddress: {{ .MAC }}
{{ end -}}
`

// TemplateArgs holds the arguments to pass to the template.
type TemplateArgs struct {
	Name            string
	BMCAddress      string
	MAC             string
	EncodedUsername string
	EncodedPassword string
}

func encodeToSecret(input string) string {
	return base64.StdEncoding.EncodeToString([]byte(input))
}

func main() {
	var username = flag.String("user", "", "username for BMC")
	var password = flag.String("password", "", "password for BMC")
	var bmcAddress = flag.String("address", "", "address URL for BMC")
	var verbose = flag.Bool("v", false, "turn on verbose output")
	var bootMAC = flag.String(
		"boot-mac", "", "specify boot MAC address of host")
	flag.Parse()

	hostName := flag.Arg(0)
	if hostName == "" {
		fmt.Fprintf(os.Stderr, "Missing name argument\n")
		os.Exit(1)
	}
	if *username == "" {
		fmt.Fprintf(os.Stderr, "Missing -user argument\n")
		os.Exit(1)
	}
	if *password == "" {
		fmt.Fprintf(os.Stderr, "Missing -password argument\n")
		os.Exit(1)
	}
	if *bmcAddress == "" {
		fmt.Fprintf(os.Stderr, "Missing -address argument\n")
		os.Exit(1)
	}

	args := TemplateArgs{
		Name:            strings.Replace(hostName, "_", "-", -1),
		BMCAddress:      *bmcAddress,
		MAC:             *bootMAC,
		EncodedUsername: encodeToSecret(*username),
		EncodedPassword: encodeToSecret(*password),
	}
	if *verbose {
		fmt.Fprintf(os.Stderr, "%v", args)
	}

	t := template.Must(template.New("yaml_out").Parse(templateBody))
	err := t.Execute(os.Stdout, args)
	if err != nil {
		fmt.Fprintf(os.Stderr, "ERROR: %s\n", err)
	}
}
