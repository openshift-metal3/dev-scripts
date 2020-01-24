package main

import (
	"fmt"
	"github.com/apparentlymart/go-cidr/cidr"
	"github.com/openshift/installer/pkg/ipnet"
	"net"
	"net/url"
	"os"
	"text/template"
)

type templater struct {
	MachineOSImageURL string

	// Ironic clouds.yaml data
	BootstrapIronicURL    string
	BootstrapInspectorURL string
	ClusterIronicURL      string
	ClusterInspectorURL   string
}

func main() {
	var templateData templater

	if len(os.Args) < 4 {
		fmt.Printf("usage: <prog> TEMPLATE_FILE NETWORK IMAGE_URL\n")
		os.Exit(1)
	}

	templateFile := os.Args[1]

	ipnet := ipnet.MustParseCIDR(os.Args[2])

	// Image URL
	url, err := url.Parse(os.Args[3])
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	templateData.MachineOSImageURL = url.String()

	// BootstrapIP
	bootstrapIP, _ := cidr.Host(&ipnet.IPNet, 2)
	templateData.BootstrapIronicURL = fmt.Sprintf("http://%s", net.JoinHostPort(bootstrapIP.String(), "6385"))
	templateData.BootstrapInspectorURL = fmt.Sprintf("http://%s", net.JoinHostPort(bootstrapIP.String(), "5050"))

	// ProvisioningIP
	ip, _ := cidr.Host(&ipnet.IPNet, 3)
	templateData.ClusterIronicURL = fmt.Sprintf("http://%s", net.JoinHostPort(ip.String(), "6385"))
	templateData.ClusterInspectorURL = fmt.Sprintf("http://%s", net.JoinHostPort(ip.String(), "5050"))

	t, err := template.New(templateFile).ParseFiles(templateFile)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	err = t.Execute(os.Stdout, templateData)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
