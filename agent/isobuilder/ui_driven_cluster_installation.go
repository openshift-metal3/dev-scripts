package main

import (
	"fmt"
	"log"
	"os"
	"path"
	"path/filepath"

	"strings"
	"time"

	resty "github.com/go-resty/resty/v2"
	"github.com/go-rod/rod"

	"github.com/go-rod/rod/lib/launcher"
	"github.com/go-rod/rod/lib/proto"
	"github.com/go-rod/rod/lib/utils" 

	"github.com/sirupsen/logrus"
)

var (
	rendezvousIP = os.Getenv("RENDEZVOUS_IP")
	ocpDir       = os.Getenv("OCP_DIR")
	baseURL     = fmt.Sprintf("http://%s:3001", rendezvousIP)
	clustersURL = fmt.Sprintf("%s%s", baseURL, path.Join("/api/assisted-install/v2/clusters"))
)

func main() {
	logrus.Info("Launching headless browser...")
	url := launcher.New().Headless(true).MustLaunch()
	browser := rod.New().ControlURL(url).MustConnect()

	defer browser.MustClose()

	page := browser.MustPage(baseURL)
	page.MustWaitLoad()

	cwd, err := os.Getwd()
	if err != nil {
		log.Fatal(err)
	}
	screenshotPath := filepath.Join(cwd, ocpDir)

	logrus.Info("Enter cluster details")
	err = clusterDetails(page, filepath.Join(screenshotPath, "01-cluster-details.png"))
	if err != nil {
		log.Fatalf("failed to enter cluster details: %v", err)
	}

	next(page)

	logrus.Info("Select virtualization bundle")
	err = virtualizationBundle(page, filepath.Join(screenshotPath, "02-operators.png"))
	if err != nil {
		log.Fatalf("failed to select virtualization bundle: %v", err)
	}

	next(page)

	logrus.Info("Await host discovery")
	err = hostDiscovery(page, filepath.Join(screenshotPath, "03-hostDiscovery.png"))
	if err != nil {
		log.Fatalf("failed awaiting host discovery: %v", err)
	}

	next(page)

	logrus.Info("Verify storage")
	err = verifyStorage(page, filepath.Join(screenshotPath, "04-storage.png"))
	if err != nil {
		log.Fatalf("failed awaiting host discovery: %v", err)
	}

	next(page)

	logrus.Info("Enter networking details")
	err = networkingDetails(page, filepath.Join(screenshotPath, "05-networking.png"))
	if err != nil {
		log.Fatalf("failed entering networking details: %v", err)
	}

	next(page)

	logrus.Info("Download credentials")
	client := resty.New()
	err = downloadCredentials(page, client, filepath.Join(screenshotPath, "06-credentials.png"))
	if err != nil {
		log.Fatalf("failed downloading credentials: %v", err)
	}

	next(page)

	logrus.Info("Review")
	err = review(page, filepath.Join(screenshotPath, "07-review.png"))
	if err != nil {
		log.Fatalf("failed review page: %v", err)
	}

	logrus.Info("Start Cluster Installation")
	err = startInstallation(page, client, filepath.Join(screenshotPath, "08-installation.png"))
	if err != nil {
		log.Fatalf("failed to start installation page: %v", err)
	}
	logrus.Info("Cluster installation started successfully.")

	waitForClusterConsoleLink(page, filepath.Join(screenshotPath, "09-installation-progress.png"))
}

func clusterDetails(page *rod.Page, path string) error {
	page.MustElement("#form-input-name-field").MustInput("abi-ove-isobuilder")
	page.MustElement("#form-input-baseDnsDomain-field").MustInput("redhat.com")

	pullSecretPath := os.Getenv("PULL_SECRET_FILE")
	secretBytes, err := os.ReadFile(pullSecretPath)
	if err != nil {
		return fmt.Errorf("failed to read pull secret file: %v", err)
	}
	pullSecret := strings.TrimSpace(string(secretBytes))
	page.MustElement("#form-input-pullSecret-field").MustInput(pullSecret)

	err = saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	return nil
}

func virtualizationBundle(page *rod.Page, path string) error {
	page.MustElement(`#bundle-virtualization`).MustClick().MustWaitEnabled()
	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	return nil
}

func hostDiscovery(page *rod.Page, path string) error {
	page.MustElement(`button[name="next"]`).MustWaitEnabled()
	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	return nil
}

func verifyStorage(page *rod.Page, path string) error {
	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	return nil
}

func networkingDetails(page *rod.Page, path string) error {
	apiVip := os.Getenv("API_VIP")
	ingressVip := os.Getenv("INGRESS_VIP")
	page.MustElement("#form-input-apiVips-0-ip-field").MustInput(apiVip)
	page.MustElement("#form-input-ingressVips-0-ip-field").MustInput(ingressVip)
	page.MustElement(`button[name="next"]`).MustWaitEnabled()

	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	return nil
}

func downloadCredentials(page *rod.Page, client *resty.Client, path string) error {
	page.MustElement(`#credentials-download-agreement`).MustClick()
	page.MustElement(`button[name="next"]`).MustWaitEnabled()

	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	time.Sleep(30 * time.Second)

	clusterID, err := getClusterID(client, clustersURL)
	if err != nil {
		return err
	}

	logrus.Info("Download credentials via api request")

	fileURL := fmt.Sprintf("%s/%s/downloads/credentials?file_name=", clustersURL, clusterID)
	saveCredentials(client, fileURL, "kubeadmin-password")
	time.Sleep(15 * time.Second)

	saveCredentials(client, fileURL, "kubeconfig")
	time.Sleep(15 * time.Second)
	return nil
}

func review(page *rod.Page, path string) error {
	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	page.MustElement(`button[name="install"]`).MustClick()
	logrus.Info("Install button clicked")
	return nil
}

func startInstallation(page *rod.Page, client *resty.Client, path string) error {
	page.MustElementR(`h2[data-ouia-component-type="PF5/Text"]`, `Installation progress`)
	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}

	return nil
}

func waitForClusterConsoleLink(page *rod.Page, path string) error {
	for {
		failMsg, _ := page.Timeout(5 * time.Second).ElementR("div.pf-v5-c-empty-state__body", `Failed on`)
		if failMsg != nil {
			logrus.Error("Cluster installation failed.")
			if err := saveFullPageScreenshot(page, path); err != nil {
				return err
			}
			return fmt.Errorf("cluster installation failed")
		}

		consoleURL, _ := page.Timeout(5 * time.Second).ElementR("button.pf-v5-c-button", `https://console-openshift-console.apps.abi-ove-isobuilder.redhat.com`)
		if consoleURL != nil {
			if visible, _ := consoleURL.Visible(); visible {
				logrus.Info("Console URL is available.")
				break
			}
		}

		logrus.Info("Cluster installation in progress. Waiting for console URL to be available.")
		time.Sleep(5 * time.Minute)
	}

	if err := saveFullPageScreenshot(page, path); err != nil {
		return err
	}

	return nil
}

func next(page *rod.Page) {
	page.MustElement(`button[name="next"]`).MustWaitEnabled().MustClick()
}

// saveFullPageScreenshot captures a full-page screenshot and saves it to the given path.
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
	logrus.Info("Screenshot saved to", path, ", with type of image/png")
	return nil
}

// getClusterID fetches the first cluster ID from the given URL using the provided client.
func getClusterID(client *resty.Client, url string) (string, error) {
	var clusters []struct {
		ID string `json:"id"`
	}

	_, err := client.R().SetResult(&clusters).Get(url)
	if err != nil {
		return "", err
	}

	return clusters[0].ID, nil
}

// saveCredentials downloads a file from the given URL and saves it under the auth directory.
func saveCredentials(client *resty.Client, url, filename string) {
	logrus.Info("Downloading ", filename)

	fileURL := fmt.Sprintf("%s%s", url, filename)
	resp, err := client.R().Get(fileURL)
	if err != nil {
		logrus.Info("Request failed:", err)
		return
	}

	downloadedFile := fmt.Sprintf("%s/auth/%s", ocpDir, filename)
	err = os.WriteFile(downloadedFile, resp.Body(), 0644)
	if err != nil {
		logrus.Errorf("Failed to save file %s: %v", downloadedFile, err)
		return
	}
	logrus.Info("File ", downloadedFile, " downloaded successfully")
}
