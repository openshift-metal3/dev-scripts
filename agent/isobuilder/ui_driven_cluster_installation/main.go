package main

import (
	"encoding/json"
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
	time.Sleep(1 * time.Minute)
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

	// Wait 1 minute before entering cluster details to allow backend initialization
	// This mimics manual usage where a user takes time to read and fill in the form
	logrus.Info("Waiting 1 minute to allow backend initialization...")
	time.Sleep(1 * time.Minute)

	logrus.Info("Enter cluster details")
	err = clusterDetails(page, filepath.Join(screenshotPath, "01-cluster-details.png"))
	if err != nil {
		log.Fatalf("failed to enter cluster details: %v", err)
	}

	next(page)

	// Wait for cluster creation to complete and operators page to load
	logrus.Info("Waiting for operators page to load...")
	maxRetries := 5
	retryDelay := 3 * time.Second

	for attempt := 1; attempt <= maxRetries; attempt++ {
		time.Sleep(retryDelay)

		// Check if we got an error page because cluster wasn't created in time
		errorMsg, _ := page.Timeout(2 * time.Second).ElementR("div", "Cluster details not found")
		if errorMsg != nil {
			if attempt < maxRetries {
				logrus.Infof("Cluster not ready yet (attempt %d/%d), waiting and reloading...", attempt, maxRetries)
				page.MustReload()
				page.MustWaitLoad()
				retryDelay = retryDelay + (2 * time.Second) // Increase wait time each retry
			} else {
				logrus.Error("Cluster creation timeout - cluster not found after multiple retries")
				saveFullPageScreenshot(page, filepath.Join(screenshotPath, "02-operators-error.png"))
				log.Fatal("Failed to load cluster - cluster details not found")
			}
		} else {
			// No error page, cluster loaded successfully
			logrus.Infof("Operators page loaded successfully (attempt %d)", attempt)
			break
		}
	}

	logrus.Info("Select virtualization bundle")

	// Save API state for debugging
	saveClusterAPIState(screenshotPath, "02-operators")

	err = virtualizationBundle(page, filepath.Join(screenshotPath, "02-operators.png"))
	if err != nil {
		log.Fatalf("failed to select virtualization bundle: %v", err)
	}

	// Wait for operators page to finish loading before clicking Next
	logrus.Info("Waiting for operators page to finish loading...")
	time.Sleep(5 * time.Second)

	next(page)

	// Save API state before host discovery
	saveClusterAPIState(screenshotPath, "03-hostDiscovery")

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

	// Save API state before starting installation
	saveClusterAPIState(screenshotPath, "07-review")

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

	// Allow UI enough time to complete the background API call to create the cluster
	time.Sleep(2 * time.Second)
	page.MustElement("button[name='next']").MustWaitEnabled()

	err = saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	return nil
}

func virtualizationBundle(page *rod.Page, path string) error {
	checkbox := page.MustElement("#bundle-virtualization")
	checkbox.MustScrollIntoView()
	checkbox.MustClick()
	// Allow UI enough time to complete the background API call
	time.Sleep(2 * time.Second)
	page.MustElement("button[name='next']").MustWaitEnabled()
	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	return nil
}

func hostDiscovery(page *rod.Page, path string) error {
	logrus.Info("Looking for Next button on Host Discovery page...")

	// Wait for button to appear with timeout, but don't keep the timeout context
	_, err := page.Timeout(10 * time.Second).Element("button[name='next']")
	if err != nil {
		logrus.Errorf("Could not find Next button: %v", err)
		// Save debug screenshot
		saveFullPageScreenshot(page, strings.Replace(path, ".png", "-error.png", 1))
		return errs.Wrap(err, "Next button not found on Host Discovery page")
	}

	logrus.Info("Found Next button, waiting for it to be enabled...")
	logrus.Info("This may take several minutes while hosts complete discovery and validations...")

	// Poll host status while waiting for Next button to be enabled
	startTime := time.Now()
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	go func() {
		clustersURL := fmt.Sprintf("http://%s:3001/api/assisted-install/v2/clusters", rendezvousIP)
		client := resty.New()

		for range ticker.C {
			var clusters []map[string]interface{}
			_, apiErr := client.R().SetResult(&clusters).Get(clustersURL)
			if apiErr == nil && len(clusters) > 0 {
				cluster := clusters[0]
				clusterID, _ := cluster["id"].(string)
				hostsURL := fmt.Sprintf("%s/%s/hosts", clustersURL, clusterID)
				var hosts []map[string]interface{}
				client.R().SetResult(&hosts).Get(hostsURL)

				elapsed := time.Since(startTime).Round(time.Second)
				logrus.Infof("Waiting %v... %d hosts found:", elapsed, len(hosts))

				for _, host := range hosts {
					hostStatus, _ := host["status"].(string)
					hostName, _ := host["requested_hostname"].(string)
					logrus.Infof("  - %s: %s", hostName, hostStatus)
				}
			}
		}
	}()

	// Use polling instead of WaitEnabled because of timeout context issues
	// Check every 5 seconds for up to 10 minutes
	maxWait := 10 * time.Minute
	pollInterval := 5 * time.Second
	deadline := time.Now().Add(maxWait)

	pollCount := 0
	screenshotPath := filepath.Dir(path)
	for time.Now().Before(deadline) {
		pollCount++

		// Get fresh button reference without timeout context
		nextButton, err := page.Element("button[name='next']")

		var isEnabled bool
		if err == nil && nextButton != nil {
			enabled, evalErr := nextButton.Eval(`() => !this.disabled`)
			if evalErr == nil && enabled != nil {
				isEnabled = enabled.Value.Bool()
			} else {
				err = evalErr
			}
		}

		// Log button state every 12 polls (every 60 seconds)
		if pollCount%12 == 0 {
			elapsed := time.Since(startTime).Round(time.Second)
			if err != nil {
				logrus.Infof("[%v] Button check #%d: Error: %v", elapsed, pollCount, err)
			} else {
				logrus.Infof("[%v] Button check #%d: Button enabled=%v", elapsed, pollCount, isEnabled)
			}
		}

		// Take screenshot every 2 minutes
		if pollCount%24 == 0 {
			elapsed := time.Since(startTime).Round(time.Second)
			minutes := int(elapsed.Minutes())

			// Scroll to bottom to show Next button area
			if nextButton != nil {
				nextButton.ScrollIntoView()
				time.Sleep(500 * time.Millisecond)
			}

			screenshotFile := filepath.Join(screenshotPath, fmt.Sprintf("03-hostDiscovery-ui-%dmin.png", minutes))
			saveFullPageScreenshot(page, screenshotFile)
		}

		if err == nil && isEnabled {
			logrus.Info("Next button is now enabled!")
			ticker.Stop()
			break
		}
		time.Sleep(pollInterval)
	}

	// Check one final time - get fresh button reference
	nextButton, err := page.Element("button[name='next']")
	var finalEnabled bool
	if err == nil && nextButton != nil {
		enabled, evalErr := nextButton.Eval(`() => !this.disabled`)
		if evalErr == nil && enabled != nil {
			finalEnabled = enabled.Value.Bool()
		}
	}

	if err != nil || !finalEnabled {
		ticker.Stop()
		saveFullPageScreenshot(page, strings.Replace(path, ".png", "-not-enabled.png", 1))
		return errs.New("timeout waiting for Next button to be enabled")
	}

	logrus.Info("Next button is enabled, saving screenshot...")
	err = saveFullPageScreenshot(page, path)
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

// saveClusterAPIState saves the cluster and hosts API state to JSON files for debugging.
func saveClusterAPIState(screenshotPath, prefix string) {
	logrus.Infof("Saving cluster API state (%s)...", prefix)
	client := resty.New()
	clustersURL := fmt.Sprintf("http://%s:3001/api/assisted-install/v2/clusters", rendezvousIP)

	var clusters []map[string]interface{}
	_, err := client.R().SetResult(&clusters).Get(clustersURL)
	if err == nil && len(clusters) > 0 {
		cluster := clusters[0]
		clusterID, _ := cluster["id"].(string)

		// Save cluster config
		clusterJSON, _ := json.MarshalIndent(cluster, "", "  ")
		clusterFile := filepath.Join(screenshotPath, prefix+"-cluster.json")
		os.WriteFile(clusterFile, clusterJSON, 0644)
		logrus.Infof("Saved cluster config to %s", clusterFile)

		// Save hosts config
		hostsURL := fmt.Sprintf("%s/%s/hosts", clustersURL, clusterID)
		var hosts []map[string]interface{}
		_, err = client.R().SetResult(&hosts).Get(hostsURL)
		if err == nil {
			hostsJSON, _ := json.MarshalIndent(hosts, "", "  ")
			hostsFile := filepath.Join(screenshotPath, prefix+"-hosts.json")
			os.WriteFile(hostsFile, hostsJSON, 0644)
			logrus.Infof("Saved %d hosts to %s", len(hosts), hostsFile)
		}
	} else {
		logrus.Warnf("Could not retrieve cluster info from API for %s", prefix)
	}
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

	if len(clusters) == 0 {
		return "", fmt.Errorf("no clusters found")
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
