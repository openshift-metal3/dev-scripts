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

	if len(os.Args) < 5 {
		fmt.Printf("usage: <prog> TEMPLATE_FILE INTERFACE NETWORK IMAGE_URL\n")
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
	bootstrapIP, _ := cidr.Host(&ipnet.IPNet, 2)
	templateData.BootstrapIronicURL = fmt.Sprintf("http://%s", net.JoinHostPort(bootstrapIP.String(), "6385"))
	templateData.BootstrapInspectorURL = fmt.Sprintf("http://%s", net.JoinHostPort(bootstrapIP.String(), "5050"))

	// ProvisioningIP
	ip, _ := cidr.Host(&ipnet.IPNet, 3)
	size, _ := ipnet.IPNet.Mask.Size()
	templateData.ProvisioningIP = fmt.Sprintf("%s/%d", ip, size)
	templateData.ClusterIronicURL = fmt.Sprintf("http://%s", net.JoinHostPort(ip.String(), "6385"))
	templateData.ClusterInspectorURL = fmt.Sprintf("http://%s", net.JoinHostPort(ip.String(), "5050"))

	// URL Host
	if ip.To4() == nil {
		templateData.ClusterProvisioningURLHost = fmt.Sprintf("[%s]", ip)
	} else {
		templateData.ClusterProvisioningURLHost = ip.String()
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
