package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"path"
	"path/filepath"

	"errors"
	"strings"
	"time"

	errs "github.com/pkg/errors"

	resty "github.com/go-resty/resty/v2"
	"github.com/go-rod/rod"

	"github.com/go-rod/rod/lib/launcher"
	"github.com/go-rod/rod/lib/proto"
	"github.com/go-rod/rod/lib/utils"

	"github.com/sirupsen/logrus"
)

var (
	clusterName  = os.Getenv("CLUSTER_NAME")
	baseDomain   = os.Getenv("BASE_DOMAIN")
	rendezvousIP = os.Getenv("RENDEZVOUS_IP")
	ocpDir       = os.Getenv("OCP_DIR")
	baseURL      = fmt.Sprintf("http://%s:3001", rendezvousIP)
	clustersURL  = fmt.Sprintf("%s%s", baseURL, path.Join("/api/assisted-install/v2/clusters"))
	downloadAttempts = 3
)

func main() {
	logrus.Info("Launching headless browser...")
	chromiumPath, _ := launcher.LookPath()
  	url := launcher.New().Bin(chromiumPath).NoSandbox(true).Headless(true).MustLaunch()
	browser := rod.New().ControlURL(url).MustConnect()
	defer browser.MustClose()

	page := browser.MustPage(baseURL)
	page.MustWaitLoad()

	cwd, err := os.Getwd()
	if err != nil {
		log.Fatal(err)
	}
	var screenshotPath string
	if filepath.IsAbs(ocpDir) {
			screenshotPath = ocpDir
	} else {
			screenshotPath = filepath.Join(cwd, ocpDir)
	}

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

	logrus.Info("Review and start cluster installation")
	err = review(page, filepath.Join(screenshotPath, "07-review.png"))
	if err != nil {
		log.Fatalf("failed review page: %v", err)
	}

	logrus.Info("Cluster installation started successfully.")
	page.MustElementR("h2", "Installation progress")

	err = waitForClusterConsoleLink(page, filepath.Join(screenshotPath, "08-installation-progress"))
	if err != nil {
		log.Fatalf("%v", err)
	}
}
func clusterDetails(page *rod.Page, path string) error {
	page.MustElement("#form-input-name-field").MustInput(clusterName)
	page.MustElement("#form-input-baseDnsDomain-field").MustInput(baseDomain)

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
	page.MustElement("#bundle-virtualization").MustClick().MustWaitEnabled()
	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	return nil
}

func hostDiscovery(page *rod.Page, path string) error {
	page.MustElement("button[name='next']").MustWaitEnabled()
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
	clusterID, err := getClusterID(client, clustersURL)
	if err != nil {
		return err
	}

	fileURL := fmt.Sprintf("%s/%s/downloads/credentials?file_name=", clustersURL, clusterID)
	err = saveCredentials(client, fileURL, "kubeadmin-password")
	if err != nil {
		return err
	}

	err = saveCredentials(client, fileURL, "kubeconfig")
	if err != nil {
		return err
	}

	page.MustElement("#credentials-download-agreement").MustClick()
	time.Sleep(5 * time.Second)

	page.MustElementR("button", "Download credentials").MustWaitEnabled()

	err = saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	return nil
}

func review(page *rod.Page, path string) error {
	installBtn := page.MustElementR("button", "Install cluster")

	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}

	installBtn.MustClick()
	logrus.Info("Install button clicked")

	return nil
}

func waitForClusterConsoleLink(page *rod.Page, path string) error {
	var i = 0
	for {
		failMsg, _ := page.Timeout(5*time.Second).ElementR("#cluster-progress-status-value", "Failed on")
		if failMsg != nil {
			if visible, _ := failMsg.Visible(); visible {
				if err := saveFullPageScreenshot(page, fmt.Sprintf("%s-%d.png", path, i)); err != nil {
					return err
				}
				return errors.New("cluster installation failed")
			}
		}
		finalizingPage, _ := page.Timeout(5*time.Second).ElementR("h4", "Finalizing")
		if finalizingPage != nil {
			if visible, _ := finalizingPage.Visible(); visible {
				logrus.Info("Console URL is available.")
				i++
				if err := saveFullPageScreenshot(page, fmt.Sprintf("%s-%d.png", path, i)); err != nil {
					return err
				}
				break
			}
		}
		logrus.Info("Cluster installation in progress. Waiting for console URL to be available.")
		err := saveFullPageScreenshot(page, fmt.Sprintf("%s-%d.png", path, i))
		if err != nil {
			return err
		}
		i++
		time.Sleep(5 * time.Minute)
	}

	return nil
}

func next(page *rod.Page) {
	page.MustElement("button[name='next']").MustWaitEnabled().MustClick()
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
func saveCredentials(client *resty.Client, url, filename string) error {
	logrus.Info("Downloading ", filename)
	fileURL := fmt.Sprintf("%s%s", url, filename)
	for i := range downloadAttempts {
		logrus.Infof("%s download attempts %d/%d", filename, i+1, downloadAttempts)
		resp, err := client.R().Get(fileURL)
		if err != nil || resp.StatusCode() != http.StatusOK {
			time.Sleep(10 * time.Second)
			continue
		}
		if resp.StatusCode() == http.StatusOK {
			downloadedFile := fmt.Sprintf("%s/auth/%s", ocpDir, filename) 
			err = os.WriteFile(downloadedFile, resp.Body(), 0644) 
			if err != nil { 
				logrus.Errorf("Failed to save file %s:%s", downloadedFile, err) 
				return err
			}
			return nil
		}
	}
	return errs.Errorf("%s was not downloaded after %d attempts", filename, downloadAttempts)
}
