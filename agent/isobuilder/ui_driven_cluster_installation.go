package main

import (
	"context"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
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
	"github.com/pkg/errors"
	"k8s.io/apimachinery/pkg/fields"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/util/sets"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/apimachinery/pkg/watch"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/cache"
	"k8s.io/client-go/tools/clientcmd"

	configv1 "github.com/openshift/api/config/v1"
	configclient "github.com/openshift/client-go/config/clientset/versioned"
	configinformers "github.com/openshift/client-go/config/informers/externalversions"
	configlisters "github.com/openshift/client-go/config/listers/config/v1"
	routeclient "github.com/openshift/client-go/route/clientset/versioned"
	timer "github.com/openshift/installer/pkg/metrics/timer"
	cov1helpers "github.com/openshift/library-go/pkg/config/clusteroperator/v1helpers"
	"github.com/openshift/library-go/pkg/route/routeapihelpers"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clientwatch "k8s.io/client-go/tools/watch"

	"github.com/sirupsen/logrus"
)

// Event holds only the fields we care about
type Event struct {
	EventTime time.Time `json:"event_time"`
	Message   string    `json:"message"`
}

// Ref from https://github.com/openshift/installer/blame/main/cmd/openshift-install/command/waitfor.go#L41-L57
const (
	// ExitCodeOperatorStabilityFailed is used when the operator stability check fails.
	// In the upstream OpenShift Installer, exit codes start from iota+3:
	//   InstallConfigError = 3
	//   InfrastructureFailed = 4
	//   BootstrapFailed = 5
	//   InstallFailed = 6
	//   OperatorStabilityFailed = 7
	// To stay consistent with that sequence, we explicitly set this to 7 here.
	ExitCodeOperatorStabilityFailed = 7

	// coStabilityThreshold defines how long a cluster operator must have
	// Progressing=False to be considered stable, in seconds.
	coStabilityThreshold float64 = 30
)

var (
	rendezvousIP = os.Getenv("RENDEZVOUS_IP")
	ocpDir       = os.Getenv("OCP_DIR")

	baseURL     = fmt.Sprintf("http://%s:3001", rendezvousIP)
	clustersURL = fmt.Sprintf("%s%s", baseURL, path.Join("/api/assisted-install/v2/clusters"))
	eventsURL   = fmt.Sprintf("%s%s", baseURL, path.Join("/api/assisted-install/v2/events"))
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
	err = cluster_details(page, filepath.Join(screenshotPath, "01-cluster-details.png"))
	if err != nil {
		log.Fatalf("failed to enter cluster details: %v", err)
	}

	next(page)

	logrus.Info("Select virtualization bundle")
	err = virtualization_bundle(page, filepath.Join(screenshotPath, "02-operators.png"))
	if err != nil {
		log.Fatalf("failed to select virtualization bundle: %v", err)
	}

	next(page)

	logrus.Info("Await host discovery")
	err = host_discovery(page, filepath.Join(screenshotPath, "03-hostDiscovery.png"))
	if err != nil {
		log.Fatalf("failed awaiting host discovery: %v", err)
	}

	next(page)

	logrus.Info("Verify storage")
	err = verify_storage(page, filepath.Join(screenshotPath, "04-storage.png"))
	if err != nil {
		log.Fatalf("failed awaiting host discovery: %v", err)
	}

	next(page)

	logrus.Info("Enter networking details")
	err = networking_details(page, filepath.Join(screenshotPath, "05-networking.png"))
	if err != nil {
		log.Fatalf("failed entering networking details: %v", err)
	}

	next(page)

	logrus.Info("Download credentials")
	client := resty.New()
	err = download_credentials(page, client, filepath.Join(screenshotPath, "06-credentials.png"))
	if err != nil {
		log.Fatalf("failed downloading credentials: %v", err)
	}

	next(page)

	logrus.Info("Review")
	err = review(page, filepath.Join(screenshotPath, "07-review.png"))
	if err != nil {
		log.Fatalf("failed review page: %v", err)
	}

	logrus.Info("Cluster Installation")
	err = start_installation(page, client, filepath.Join(screenshotPath, "08-installation.png"))
	if err != nil {
		log.Fatalf("failed to start installation page: %v", err)
	}
	logrus.Info("Cluster installation started successfully.")

	err = monitor_installation()
	if err != nil {
		log.Fatalf("failed review page: %v", err)
	}
}

func cluster_details(page *rod.Page, path string) error {
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

func virtualization_bundle(page *rod.Page, path string) error {
	page.MustElement(`#bundle-virtualization`).MustClick().MustWaitEnabled()
	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	return nil
}

func host_discovery(page *rod.Page, path string) error {
	page.MustElement(`button[name="next"]`).MustWaitEnabled()
	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	return nil
}

func verify_storage(page *rod.Page, path string) error {
	err := saveFullPageScreenshot(page, path)
	if err != nil {
		return err
	}
	return nil
}

func networking_details(page *rod.Page, path string) error {
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

func download_credentials(page *rod.Page, client *resty.Client, path string) error {
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
	logrus.Info("install button clicked...")
	return nil
}

func start_installation(page *rod.Page, client *resty.Client, path string) error {
	page.MustElementR(`h2[data-ouia-component-type="PF5/Text"]`, `Installation progress`)
	err := saveFullPageScreenshot(page, path)
	if err != nil {
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

// monitor_installation tracks the progress of an OpenShift installation in an OVE (Open Virtualized Environment) setup.
// Since the `.openshift_install_state.json` file is unavailable in OVE, the usual `agent wait-for` commands cannot be used.
// Instead, this function monitors the installation by polling the events API.
// It waits for the bootstrap process to complete first, then waits for the entire installation to finish.
// Returns an error if the installation fails or encounters issues.
func monitor_installation() error {
	waitForBootstrapComplete()

	if err := waitForInstallComplete(); err != nil {
		return err
	}

	return nil
}

// waitForBootstrapComplete continuously polls the Assisted Service API for cluster events
// until bootstrap is complete. It works by:
//
//  1. Fetching events from the Assisted Service endpoint on each iteration.
//  2. Printing all available events on the first run, and only new events thereafter.
//  3. Tracking the timestamp of the last seen event to avoid re-printing duplicates.
//  4. Stopping once the API becomes unreachable, which happens when the rendezvous
//     host reboots — signaling that bootstrap is complete.
//
// Poll every 30 seconds until bootstrap is complete.
func waitForBootstrapComplete() {
	var lastSeen time.Time
	firstRun := true
	for {
		events, err := fetchEvents(eventsURL)
		if err != nil {
			logrus.Info("Assisted service API is unreachable (rendezvous host reboot). Bootstrap complete, stopping polling")
			break
		}

		for _, e := range events {
			// On first run, print all available events
			if firstRun || e.EventTime.After(lastSeen) {
				logrus.Infof("%s", e.Message)
				if e.EventTime.After(lastSeen) {
					lastSeen = e.EventTime
				}
			}
		}
		firstRun = false
		time.Sleep(30 * time.Second)
	}
}

// fetchEvents fetches events from the given URL and unmarshals the JSON response into a slice of Event.
func fetchEvents(url string) ([]Event, error) {
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("non-OK HTTP status: %s", resp.Status)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var events []Event
	if err := json.Unmarshal(body, &events); err != nil {
		return nil, err
	}
	return events, nil
}

// Rest of the below code is resued as is from https://github.com/openshift/installer/blame/main/cmd/openshift-install/command/waitfor.go

// WaitForInstallComplete waits for cluster to complete installation, checks for operator stability
// and logs cluster information when successful.
// copy-paste from https://github.com/openshift/installer/blame/main/cmd/openshift-install/command/waitfor.go#L63
func waitForInstallComplete() error {
	ctx := context.Background()
	config, err := clientcmd.BuildConfigFromFlags("", (fmt.Sprintf("%s/auth/kubeconfig", ocpDir)))
	if err != nil {
		return err
	}
	if err := waitForInitializedCluster(ctx, config); err != nil {
		return err
	}

	if err := addRouterCAToClusterCA(ctx, config); err != nil {
		return err
	}

	if err := waitForStableOperators(ctx, config); err != nil {
		return err
	}

	consoleURL, err := getConsole(ctx, config)
	if err != nil {
		logrus.Warnf("Cluster does not have a console available: %v", err)
	}
	return logComplete(consoleURL)
}

// waitForInitializedCluster watches the ClusterVersion waiting for confirmation
// that the cluster has been initialized.
// copy-paste from https://github.com/openshift/installer/blame/main/cmd/openshift-install/command/waitfor.go#L86
func waitForInitializedCluster(ctx context.Context, config *rest.Config) error {
	timeout := 60 * time.Minute

	untilTime := time.Now().Add(timeout)
	timezone, _ := untilTime.Zone()
	logrus.Infof("Waiting up to %v (until %v %s) for the cluster at %s to initialize...",
		timeout, untilTime.Format(time.Kitchen), timezone, config.Host)
	cc, err := configclient.NewForConfig(config)
	if err != nil {
		return errors.Wrap(err, "failed to create a config client")
	}
	clusterVersionContext, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	failing := configv1.ClusterStatusConditionType("Failing")
	timer.StartTimer("Cluster Operators Available")
	var lastError string
	_, err = clientwatch.UntilWithSync(
		clusterVersionContext,
		cache.NewListWatchFromClient(cc.ConfigV1().RESTClient(), "clusterversions", "", fields.OneTermEqualSelector("metadata.name", "version")),
		&configv1.ClusterVersion{},
		nil,
		func(event watch.Event) (bool, error) {
			switch event.Type {
			case watch.Added, watch.Modified:
				cv, ok := event.Object.(*configv1.ClusterVersion)
				if !ok {
					logrus.Warnf("Expected a ClusterVersion object but got a %q object instead", event.Object.GetObjectKind().GroupVersionKind())
					return false, nil
				}
				if cov1helpers.IsStatusConditionTrue(cv.Status.Conditions, configv1.OperatorAvailable) &&
					cov1helpers.IsStatusConditionFalse(cv.Status.Conditions, failing) &&
					cov1helpers.IsStatusConditionFalse(cv.Status.Conditions, configv1.OperatorProgressing) {
					timer.StopTimer("Cluster Operators Available")
					return true, nil
				}
				if cov1helpers.IsStatusConditionTrue(cv.Status.Conditions, failing) {
					lastError = cov1helpers.FindStatusCondition(cv.Status.Conditions, failing).Message
				} else if cov1helpers.IsStatusConditionTrue(cv.Status.Conditions, configv1.OperatorProgressing) {
					lastError = cov1helpers.FindStatusCondition(cv.Status.Conditions, configv1.OperatorProgressing).Message
				}
				logrus.Debugf("Still waiting for the cluster to initialize: %s", lastError)
				return false, nil
			}
			logrus.Debug("Still waiting for the cluster to initialize...")
			return false, nil
		},
	)

	if err == nil {
		logrus.Debug("Cluster is initialized")
		return nil
	}

	if lastError != "" {
		if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			return errors.Errorf("failed to initialize the cluster: %s", lastError)
		}

		return errors.Wrapf(err, "failed to initialize the cluster: %s", lastError)
	}

	return errors.Wrap(err, "failed to initialize the cluster")
}

// waitForStableOperators ensures that each cluster operator is "stable", i.e. the
// operator has not been in a progressing state for at least a certain duration,
// 30 seconds by default. Returns an error if any operator does meet this threshold
// after a deadline, 30 minutes by default.
// copy-paste from https://github.com/openshift/installer/blame/main/cmd/openshift-install/command/waitfor.go#161
func waitForStableOperators(ctx context.Context, config *rest.Config) error {
	timer.StartTimer("Cluster Operators Stable")

	stabilityCheckDuration := 30 * time.Minute
	stabilityContext, cancel := context.WithTimeout(ctx, stabilityCheckDuration)
	defer cancel()

	untilTime := time.Now().Add(stabilityCheckDuration)
	timezone, _ := untilTime.Zone()
	logrus.Infof("Waiting up to %v (until %v %s) to ensure each cluster operator has finished progressing...",
		stabilityCheckDuration, untilTime.Format(time.Kitchen), timezone)

	cc, err := configclient.NewForConfig(config)
	if err != nil {
		return errors.Wrap(err, "failed to create a config client")
	}
	configInformers := configinformers.NewSharedInformerFactory(cc, 0)
	clusterOperatorInformer := configInformers.Config().V1().ClusterOperators().Informer()
	clusterOperatorLister := configInformers.Config().V1().ClusterOperators().Lister()
	configInformers.Start(ctx.Done())
	if !cache.WaitForCacheSync(ctx.Done(), clusterOperatorInformer.HasSynced) {
		return fmt.Errorf("informers never started")
	}

	waitErr := wait.PollUntilContextCancel(stabilityContext, 1*time.Second, true, waitForAllClusterOperators(clusterOperatorLister))
	if waitErr != nil {
		fmt.Errorf("Error checking cluster operator Progressing status: %q", waitErr)
		stableOperators, unstableOperators, err := currentOperatorStability(clusterOperatorLister)
		if err != nil {
			fmt.Errorf("Error checking final cluster operator Progressing status: %q", err)
		}
		logrus.Debugf("These cluster operators were stable: [%s]", strings.Join(sets.List(stableOperators), ", "))
		fmt.Errorf("These cluster operators were not stable: [%s]", strings.Join(sets.List(unstableOperators), ", "))

		logrus.Exit(ExitCodeOperatorStabilityFailed)
	}

	timer.StopTimer("Cluster Operators Stable")

	logrus.Info("All cluster operators have completed progressing")

	return nil
}

// getConsole returns the console URL from the route 'console' in namespace openshift-console.
// copy-paste from https://github.com/openshift/installer/blame/main/cmd/openshift-install/command/waitfor.go#L210
func getConsole(ctx context.Context, config *rest.Config) (string, error) {
	url := ""
	// Need to keep these updated if they change
	consoleNamespace := "openshift-console"
	consoleRouteName := "console"
	rc, err := routeclient.NewForConfig(config)
	if err != nil {
		return "", errors.Wrap(err, "creating a route client")
	}

	consoleRouteTimeout := 2 * time.Minute
	logrus.Infof("Checking to see if there is a route at %s/%s...", consoleNamespace, consoleRouteName)
	consoleRouteContext, cancel := context.WithTimeout(ctx, consoleRouteTimeout)
	defer cancel()
	// Poll quickly but only log when the response
	// when we've seen 15 of the same errors or output of
	// no route in a row (to show we're still alive).
	logDownsample := 15
	silenceRemaining := logDownsample
	timer.StartTimer("Console")
	wait.Until(func() {
		route, err := rc.RouteV1().Routes(consoleNamespace).Get(ctx, consoleRouteName, metav1.GetOptions{})
		if err == nil {
			logrus.Debugf("Route found in openshift-console namespace: %s", consoleRouteName)
			if uri, _, err2 := routeapihelpers.IngressURI(route, ""); err2 == nil {
				url = uri.String()
				logrus.Debug("OpenShift console route is admitted")
				cancel()
			} else {
				err = err2
			}
		} else if apierrors.IsNotFound(err) {
			logrus.Debug("OpenShift console route does not exist")
			cancel()
		}

		if err != nil {
			silenceRemaining--
			if silenceRemaining == 0 {
				logrus.Debugf("Still waiting for the console route: %v", err)
				silenceRemaining = logDownsample
			}
		}
	}, 2*time.Second, consoleRouteContext.Done())
	err = consoleRouteContext.Err()
	if err != nil && !errors.Is(err, context.Canceled) {
		return url, errors.Wrap(err, "waiting for openshift-console URL")
	}
	if url == "" {
		return url, errors.New("could not get openshift-console URL")
	}
	timer.StopTimer("Console")
	return url, nil
}

// logComplete prints info upon completion.
// copy-paste from https://github.com/openshift/installer/blame/main/cmd/openshift-install/command/waitfor.go#L265
func logComplete(consoleURL string) error {
	kubeconfig := filepath.Join(ocpDir, "auth", "kubeconfig")
	pwFile := filepath.Join(ocpDir, "auth", "kubeadmin-password")
	pw, err := os.ReadFile(pwFile)
	if err != nil {
		return err
	}
	logrus.Info("Install complete!")
	logrus.Infof("To access the cluster as the system:admin user when using 'oc', run\n    export KUBECONFIG=%s", kubeconfig)
	if consoleURL != "" {
		logrus.Infof("Access the OpenShift web-console here: %s", consoleURL)
		logrus.Infof("Login to the console with user: %q, and password: %q", "kubeadmin", pw)
	}
	return nil
}

// addRouterCAToClusterCA adds router CA to cluster CA in kubeconfig.
// copy-paste from https://github.com/openshift/installer/blame/main/cmd/openshift-install/command/waitfor.go#L290
func addRouterCAToClusterCA(ctx context.Context, config *rest.Config) (err error) {
	client, err := kubernetes.NewForConfig(config)
	if err != nil {
		return errors.Wrap(err, "creating a Kubernetes client")
	}

	// Configmap may not exist. log and accept not-found errors with configmap.
	caConfigMap, err := client.CoreV1().ConfigMaps("openshift-config-managed").Get(ctx, "default-ingress-cert", metav1.GetOptions{})
	if err != nil {
		return errors.Wrap(err, "fetching default-ingress-cert configmap from openshift-config-managed namespace")
	}

	routerCrtBytes := []byte(caConfigMap.Data["ca-bundle.crt"])
	kubeconfig := filepath.Join(ocpDir, "auth", "kubeconfig")
	kconfig, err := clientcmd.LoadFromFile(kubeconfig)
	if err != nil {
		return errors.Wrap(err, "loading kubeconfig")
	}

	if kconfig == nil || len(kconfig.Clusters) == 0 {
		return errors.New("kubeconfig is missing expected data")
	}

	for _, c := range kconfig.Clusters {
		clusterCABytes := c.CertificateAuthorityData
		if len(clusterCABytes) == 0 {
			return errors.New("kubeconfig CertificateAuthorityData not found")
		}
		certPool := x509.NewCertPool()
		if !certPool.AppendCertsFromPEM(clusterCABytes) {
			return errors.New("cluster CA found in kubeconfig not valid PEM format")
		}
		if !certPool.AppendCertsFromPEM(routerCrtBytes) {
			return errors.New("ca-bundle.crt from default-ingress-cert configmap not valid PEM format")
		}

		routerCrtBytes := append(routerCrtBytes, clusterCABytes...)
		c.CertificateAuthorityData = routerCrtBytes
	}
	if err := clientcmd.WriteToFile(*kconfig, kubeconfig); err != nil {
		return errors.Wrap(err, "writing kubeconfig")
	}
	return nil
}

// copy-paste from https://github.com/openshift/installer/blame/main/cmd/openshift-install/command/waitfor.go#L344
func waitForAllClusterOperators(clusterOperatorLister configlisters.ClusterOperatorLister) func(ctx context.Context) (bool, error) {
	previouslyStableOperators := sets.Set[string]{}

	return func(ctx context.Context) (bool, error) {
		stableOperators, unstableOperators, err := currentOperatorStability(clusterOperatorLister)
		if err != nil {
			return false, err
		}
		if newlyStableOperators := stableOperators.Difference(previouslyStableOperators); len(newlyStableOperators) > 0 {
			for _, name := range sets.List(newlyStableOperators) {
				logrus.Debugf("Cluster Operator %s is stable", name)
			}
		}
		if newlyUnstableOperators := previouslyStableOperators.Difference(stableOperators); len(newlyUnstableOperators) > 0 {
			for _, name := range sets.List(newlyUnstableOperators) {
				logrus.Debugf("Cluster Operator %s became unstable", name)
			}
		}
		previouslyStableOperators = stableOperators

		if len(unstableOperators) == 0 {
			return true, nil
		}

		return false, nil
	}
}

// copy-paste from https://github.com/openshift/installer/blame/main/cmd/openshift-install/command/waitfor.go#L372
func currentOperatorStability(clusterOperatorLister configlisters.ClusterOperatorLister) (sets.Set[string], sets.Set[string], error) {
	clusterOperators, err := clusterOperatorLister.List(labels.Everything())
	if err != nil {
		return nil, nil, err // lister should never fail
	}

	stableOperators := sets.Set[string]{}
	unstableOperators := sets.Set[string]{}
	for _, clusterOperator := range clusterOperators {
		name := clusterOperator.Name
		progressing := cov1helpers.FindStatusCondition(clusterOperator.Status.Conditions, configv1.OperatorProgressing)
		if progressing == nil {
			logrus.Debugf("Cluster Operator %s progressing == nil", name)
			unstableOperators.Insert(name)
			continue
		}
		if meetsStabilityThreshold(progressing) {
			stableOperators.Insert(name)
		} else {
			logrus.Debugf("Cluster Operator %s is Progressing=%s LastTransitionTime=%v DurationSinceTransition=%.fs Reason=%s Message=%s", name, progressing.Status, progressing.LastTransitionTime.Time, time.Since(progressing.LastTransitionTime.Time).Seconds(), progressing.Reason, progressing.Message)
			unstableOperators.Insert(name)
		}
	}

	return stableOperators, unstableOperators, nil
}

// copy-paste from https://github.com/openshift/installer/blame/main/cmd/openshift-install/command/waitfor.go#L399
func meetsStabilityThreshold(progressing *configv1.ClusterOperatorStatusCondition) bool {
	return progressing.Status == configv1.ConditionFalse && time.Since(progressing.LastTransitionTime.Time).Seconds() > coStabilityThreshold
}
