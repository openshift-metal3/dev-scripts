package main

import (
	"fmt"
	"github.com/apparentlymart/go-cidr/cidr"
	"github.com/openshift/installer/pkg/ipnet"
	"net"
	"net/url"
	"os"
	"strings"
	"text/template"
)

type templater struct {
	ProvisioningInterface      string
	ProvisioningIP             string
	ProvisioningDHCPRange      string
	ClusterProvisioningURLHost string
	MachineOSImageURL          string

	// Ironic clouds.yaml data
	BootstrapIronicURL    string
	BootstrapInspectorURL string
	ClusterIronicURL      string
	ClusterInspectorURL   string
}

func main() {
	var templateData templater

	if len(os.Args) < 7 {
		fmt.Printf("usage: <prog> TEMPLATE_FILE INTERFACE NETWORK BOOTSTRAP_IP CLUSTER_IP IMAGE_URL\n")
		os.Exit(1)
	}

	templateFile := os.Args[1]

	templateData.ProvisioningInterface = os.Args[2]

	ipnet := ipnet.MustParseCIDR(os.Args[3])

	// Image URL
	url, err := url.Parse(os.Args[4])
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	templateData.MachineOSImageURL = url.String()

	// DHCP Range
	startIP, _ := cidr.Host(&ipnet.IPNet, 10)
	endIP, _ := cidr.Host(&ipnet.IPNet, 100)
	templateData.ProvisioningDHCPRange = fmt.Sprintf("%s,%s", startIP, endIP)

	// BootstrapIP
	bootstrapIP := os.Args[5]
	templateData.BootstrapIronicURL = fmt.Sprintf("http://%s", net.JoinHostPort(bootstrapIP, "6385"))
	templateData.BootstrapInspectorURL = fmt.Sprintf("http://%s", net.JoinHostPort(bootstrapIP, "5050"))

	// ProvisioningIP
	ip := os.Args[6]
	size, _ := ipnet.IPNet.Mask.Size()
	templateData.ProvisioningIP = fmt.Sprintf("%s/%d", ip, size)
	templateData.ClusterIronicURL = fmt.Sprintf("http://%s", net.JoinHostPort(ip, "6385"))
	templateData.ClusterInspectorURL = fmt.Sprintf("http://%s", net.JoinHostPort(ip, "5050"))

	// URL Host
	if strings.Contains(ip, ":") {
		templateData.ClusterProvisioningURLHost = fmt.Sprintf("[%s]", ip)
	} else {
		templateData.ClusterProvisioningURLHost = ip
	}

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
