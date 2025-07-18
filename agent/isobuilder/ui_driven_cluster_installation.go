package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
	"log"

	resty "github.com/go-resty/resty/v2"
	"github.com/go-rod/rod"
	"github.com/go-rod/rod/lib/launcher"
	"github.com/go-rod/rod/lib/proto"
	"github.com/go-rod/rod/lib/utils"
)

func main() {
	fmt.Println("Launching headless browser...")
	url := launcher.New().Headless(true).MustLaunch()
	browser := rod.New().ControlURL(url).MustConnect()
	defer browser.MustClose()

	rendezvousIP := os.Getenv("RENDEZVOUS_IP")
	page := browser.MustPage(fmt.Sprintf("http://%s:3001/", rendezvousIP))
	page.MustWaitLoad()

	cwd, err := os.Getwd()
	if err != nil {
		log.Fatal(err)
	}
	ocpDir := os.Getenv("OCP_DIR")
	screenshotPath := filepath.Join(cwd, ocpDir)

	fmt.Println("==== Enter cluster details ====")
	err = cluster_details(page, screenshotPath)
	if err != nil {
		log.Fatalf("failed to enter cluster details: %v", err)
	}
	next(page)

	fmt.Println("==== Select virtualization bundle ====")
	err = virtualization_bundle(page, screenshotPath)
	if err != nil {
		log.Fatalf("failed to select virtualization bundle: %v", err)
	}

	next(page)

	fmt.Println("==== Await host discovery ====")
	err = host_discovery(page, screenshotPath)
	if err != nil {
		log.Fatalf("failed awaiting host discovery: %v", err)
	}

	next(page)

	fmt.Println("==== Verify storage ====")
	err = verify_storage(page, screenshotPath)
	if err != nil {
		log.Fatalf("failed awaiting host discovery: %v", err)
	}

	next(page)

	fmt.Println("==== Enter networking details ====")
	err = networking_details(page, screenshotPath)
	if err != nil {
		log.Fatalf("failed entering networking details: %v", err)
	}

	next(page)

	fmt.Println("==== Download credentials ====")
	err = download_credentials(page, screenshotPath, rendezvousIP)
	if err != nil {
		log.Fatalf("failed downloading credentials: %v", err)
	}
	next(page)
	
	fmt.Println("==== Review ====")
	err =review(page, screenshotPath)
	if err != nil {
		log.Fatalf("failed review page: %v", err)
	}
	
	fmt.Println("==== Installation progress ====")
	err = installation_progress(page, screenshotPath)
	if err != nil {
		log.Fatalf("failed review page: %v", err)
	}
	fmt.Println("Cluster installation started successfully.")
}

func cluster_details(page *rod.Page, screenshotPath string) error {
	page.MustElement("#form-input-name-field").MustInput("abi-ove-isobuilder")
	page.MustElement("#form-input-baseDnsDomain-field").MustInput("redhat.com")

	pullSecretPath := os.Getenv("PULL_SECRET_FILE")
	secretBytes, err := os.ReadFile(pullSecretPath)
	if err != nil {
		return fmt.Errorf("failed to read pull secret file: %v", err)
	}
	pullSecret := strings.TrimSpace(string(secretBytes))
	page.MustElement("#form-input-pullSecret-field").MustInput(pullSecret)

	path := filepath.Join(screenshotPath, "01-cluster-details.png")
	err = saveFullPageScreenshot(page, path)
	if err != nil { 
		return err
	}
	return nil
}

func virtualization_bundle(page *rod.Page, screenshotPath string) error {
	page.MustElement(`#bundle-virtualization`).MustClick().MustWaitEnabled()
	path := filepath.Join(screenshotPath, "02-operators.png")
	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	return nil
}

func host_discovery(page *rod.Page, screenshotPath string) error {
	page.MustElement(`button[name="next"]`).MustWaitEnabled()
	path := filepath.Join(screenshotPath, "03-hostDiscovery.png")
	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	return nil
}

func verify_storage(page *rod.Page, screenshotPath string) error {
	path := filepath.Join(screenshotPath, "04-storage.png")
	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	return nil
}

func networking_details(page *rod.Page, screenshotPath string) error {
	// To Do: Do not hardcode the VIPS
	page.MustElement("#form-input-apiVips-0-ip-field").MustInput("192.168.111.50")
	page.MustElement("#form-input-ingressVips-0-ip-field").MustInput("192.168.111.51")
	page.MustElement(`button[name="next"]`).MustWaitEnabled()

	path := filepath.Join(screenshotPath, "05-networking.png")
	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	return nil
}

func download_credentials(page *rod.Page, screenshotPath, rendezvousIP string) error {
	page.MustElement(`#credentials-download-agreement`).MustClick()
	page.MustElement(`button[name="next"]`).MustWaitEnabled()
	
	path := filepath.Join(screenshotPath, "06-credentials.png")
	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	time.Sleep(30 * time.Second)

	client := resty.New()
	apiURL := fmt.Sprintf("http://%s:3001/api/assisted-install/v2/clusters/", rendezvousIP)
	clusterID, err := getClusterID(client, apiURL)
	if err != nil {
    	return err
	}
	apiURL = apiURL+clusterID

	fmt.Println("Download credentials via api request")

	downloadCredentials(client, apiURL, "kubeadmin-password")
	time.Sleep(15 * time.Second) 

    downloadCredentials(client, apiURL, "kubeconfig")
	time.Sleep(15 * time.Second)
	return nil
}

func review(page *rod.Page, screenshotPath string) error {
	path := filepath.Join(screenshotPath, "07-review.png")
	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	page.MustElement(`button[name="install"]`).MustClick()
	fmt.Println("install button clicked...")
	return nil
}

func installation_progress(page *rod.Page, screenshotPath string) error {
	page.MustElementR(`h2[data-ouia-component-type="PF5/Text"]`, `Installation progress`)
	path := filepath.Join(screenshotPath, "08-installation.png")
	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	return nil
}

func saveFullPageScreenshot(page *rod.Page, path string) error {
    result, err := page.Evaluate(rod.Eval(`() => {
        return {
            width: document.body.scrollWidth,
            height: document.body.scrollHeight
        }
    }`))
    if err != nil {
        return fmt.Errorf("failed to evaluate page size: %w", err)
    }

    width := int(result.Value.Get("width").Int())
    height := int(result.Value.Get("height").Int())

    err = page.SetViewport(&proto.EmulationSetDeviceMetricsOverride{
        Width:             int(width),
        Height:            int(height),
        DeviceScaleFactor: 1,
        Mobile:            false,
    })
    if err != nil {
        return fmt.Errorf("failed to set viewport: %w", err)
    }

    screenshot, err := page.Screenshot(false, nil)
    if err != nil {
        return fmt.Errorf("failed to take screenshot: %w", err)
    }

    if err := utils.OutputFile(path, screenshot); err != nil {
        return fmt.Errorf("failed to save screenshot: %w", err)
    }
	fmt.Println("Screenshot saved to", path, ", with type of image/png")
    return nil
}

func next(page *rod.Page){
	page.MustElement(`button[name="next"]`).MustWaitEnabled().MustClick()
}

func getClusterID(client *resty.Client, apiURL string) (string, error) {
    var clusters []struct {
        ID string `json:"id"`
    }

    resp, err := client.R().
        SetResult(&clusters).
        Get(apiURL)
    if err != nil {
		return "", err
    }

    if resp.IsError() {
		return "", err
    }
	return clusters[0].ID, nil
}

func downloadCredentials(client *resty.Client, apiURL, filename string){
    fmt.Println("Downloading ", filename)

	apiURL = apiURL+"/downloads/credentials?file_name="+filename
    resp, err := client.R().Get(apiURL)
    if err != nil {
        fmt.Println("Request failed:", err)
        return
    }
	
    downloadedFile:="/home/test/dev-scripts/ocp/ostest/auth/"+filename
    err = os.WriteFile(downloadedFile, resp.Body(), 0644)
    if err != nil {
        fmt.Println("Failed to save file %s:", downloadedFile, err)
        return
    }
	fmt.Println("File", downloadedFile, "downloaded successfully")
}

