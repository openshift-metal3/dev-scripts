package main

import (
	"errors"
	"flag"
	"fmt"
	"net"
	"net/url"
	"os"
	"strings"
	"text/template"

	"github.com/apparentlymart/go-cidr/cidr"
	"github.com/openshift/installer/pkg/ipnet"
)

type templater struct {
	ProvisioningInterface      string
	ProvisioningIP             string
	ProvisioningDHCPRange      string
	ClusterProvisioningURLHost string
	MachineOSImageURL          string

	// Ironic clouds.yaml data
	AuthType                string
	BootstrapIronicURL      string
	BootstrapInspectorURL   string
	ClusterIronicURL        string
	ClusterInspectorURL     string
	IronicUser              string
	IronicPassword          string
	InspectorUser           string
	InspectorPassword       string
	OCPVersionUsesInspector bool
}

func readCreds(fileName string) (user string, password string, err error) {
	if fileName == "" {
		err = errors.New("expected credentials")
		return
	}

	content, err := os.ReadFile(fileName)
	if err != nil {
		err = fmt.Errorf("%s: %w", fileName, err)
		return
	}

	parts := strings.SplitN(string(content), ":", 2)
	if len(parts) < 2 {
		err = fmt.Errorf("%s: must contain a colon as a separator", fileName)
		return
	}

	user = strings.TrimSpace(parts[0])
	password = strings.TrimSpace(parts[1])
	if user == "" || password == "" {
		err = fmt.Errorf("%s: empty user or password", fileName)
	}

	return
}

func main() {

	var templateFile string
	var bootstrapIP string
	var ironicCredFile string
	var inspectorCredFile string

	bootstrapCmd := flag.NewFlagSet("bootstrap", flag.ExitOnError)
	bootstrapCmd.StringVar(&templateFile, "template-file", "", "Template File")
	bootstrapCmd.StringVar(&bootstrapIP, "bootstrap-ip", "", "Bootstrap IP address")

	var provisioningInterface string
	var provisioningNetwork string
	var clusterIP string
	var imageURL string
	var ocpVersionUsesInspector bool

	noauthCmd := flag.NewFlagSet("noauth", flag.ExitOnError)
	noauthCmd.StringVar(&templateFile, "template-file", "", "Template File")
	noauthCmd.StringVar(&provisioningInterface, "provisioning-interface", "", "Cluster provisioning Interface")
	noauthCmd.StringVar(&provisioningNetwork, "provisioning-network", "", "Provisioning Network CIDR")
	noauthCmd.StringVar(&imageURL, "image-url", "", "Image URL")
	noauthCmd.StringVar(&bootstrapIP, "bootstrap-ip", "", "Bootstrap IP address")
	noauthCmd.StringVar(&clusterIP, "cluster-ip", "", "Cluster IP address")

	httpBasicCmd := flag.NewFlagSet("http_basic", flag.ExitOnError)
	httpBasicCmd.StringVar(&templateFile, "template-file", "", "Template File")
	httpBasicCmd.StringVar(&provisioningInterface, "provisioning-interface", "", "Cluster provisioning Interface")
	httpBasicCmd.StringVar(&provisioningNetwork, "provisioning-network", "", "Provisioning Network CIDR")
	httpBasicCmd.StringVar(&imageURL, "image-url", "", "Image URL")
	httpBasicCmd.StringVar(&bootstrapIP, "bootstrap-ip", "", "Bootstrap IP address")
	httpBasicCmd.StringVar(&clusterIP, "cluster-ip", "", "Cluster IP address")
	httpBasicCmd.BoolVar(&ocpVersionUsesInspector, "ocp-version-uses-inspector", false, "")

	httpBasicCmd.StringVar(&ironicCredFile, "ironic-basic-auth", "", "ironic credentials: file with <user>:<password>")
	httpBasicCmd.StringVar(&inspectorCredFile, "inspector-basic-auth", "", "inspector crdentials: file with <user>:<password>")

	if len(os.Args) < 2 {
		fmt.Printf("Expected 'bootstrap' 'noauth' or 'http_basic' subcommands\n")
		os.Exit(1)
	}

	var auth = os.Args[1]
	var templateData templater

	switch auth {
	case "bootstrap":
		bootstrapCmd.Parse(os.Args[2:])
		if !(bootstrapCmd.NFlag() == 2 && bootstrapCmd.NArg() == 0) {
			os.Exit(1)
		}

		templateData.BootstrapIronicURL = fmt.Sprintf("http://%s", net.JoinHostPort(bootstrapIP, "6385"))
		templateData.BootstrapInspectorURL = fmt.Sprintf("http://%s", net.JoinHostPort(bootstrapIP, "5050"))
	case "noauth":
		noauthCmd.Parse(os.Args[2:])
		if !(noauthCmd.NFlag() == 6 && noauthCmd.NArg() == 0) {
			fmt.Printf("Usage: <prog> noauth -template-file=TEMPLATE_FILE -provisioning-interface=INTERFACE -provisioning-network=NETWORK -bootstrap-ip=BOOTSTRAP_IP -cluster-ip=CLUSTER_IP -image-url=IMAGE_URL\n")
			os.Exit(1)
		}

		templateData.AuthType = "none"
		templateData.OCPVersionUsesInspector = true
	case "http_basic":
		httpBasicCmd.Parse(os.Args[2:])
		if !(httpBasicCmd.NFlag() >= 7 && httpBasicCmd.NArg() == 0) {
			fmt.Printf("Usage: <prog> http_basic [-ocp-version-uses-inspector] -ironic-basic-auth=<user>:<password> [-inspector-basic-auth=<user>:<password>] -template-file=TEMPLATE_FILE -provisioning-interface=INTERFACE -provisioning-network=NETWORK -bootstrap-ip=BOOTSTRAP_IP -cluster-ip=CLUSTER_IP -image-url=IMAGE_URL\n")
			os.Exit(1)
		}

		ironicUser, ironicPassword, err := readCreds(ironicCredFile)
		if err != nil {
			fmt.Println(err)
			os.Exit(1)
		}

		var inspectorUser, inspectorPassword string
		if ocpVersionUsesInspector {
			inspectorUser, inspectorPassword, err = readCreds(inspectorCredFile)
			if err != nil {
				fmt.Println(err)
				os.Exit(1)
			}
		}

		templateData.AuthType = "http_basic"
		templateData.IronicUser = ironicUser
		templateData.IronicPassword = ironicPassword

		if ocpVersionUsesInspector {
			templateData.InspectorUser = inspectorUser
			templateData.InspectorPassword = inspectorPassword
			templateData.OCPVersionUsesInspector = true
		}

	default:
		fmt.Println("Expected 'bootstrap' 'noauth' or 'http_basic' subcommands\n")
		os.Exit(1)
	}

	if auth != "bootstrap" {
		templateData.ProvisioningInterface = provisioningInterface

		ipnet := ipnet.MustParseCIDR(provisioningNetwork)

		// Image URL
		url, err := url.Parse(imageURL)
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
		templateData.BootstrapIronicURL = fmt.Sprintf("http://%s", net.JoinHostPort(bootstrapIP, "6385"))
		templateData.BootstrapInspectorURL = fmt.Sprintf("http://%s", net.JoinHostPort(bootstrapIP, "5050"))

		// ProvisioningIP
		size, _ := ipnet.IPNet.Mask.Size()
		templateData.ProvisioningIP = fmt.Sprintf("%s/%d", clusterIP, size)
		templateData.ClusterIronicURL = fmt.Sprintf("https://%s", net.JoinHostPort(clusterIP, "6385"))
		templateData.ClusterInspectorURL = fmt.Sprintf("https://%s", net.JoinHostPort(clusterIP, "5050"))

		// URL Host
		if strings.Contains(clusterIP, ":") {
			templateData.ClusterProvisioningURLHost = fmt.Sprintf("[%s]", clusterIP)
		} else {
			templateData.ClusterProvisioningURLHost = clusterIP
		}
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
