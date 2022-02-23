package jobs

import "encoding/xml"

var (
	ignoreTestCases = map[string]struct{}{
		"[sig-arch] Monitor cluster while tests execute": {},
	}
)

type TestCaseSkipped struct {
	XMLName xml.Name `xml:"skipped"`
	Message string   `xml:"message,attr"`
}

type TestCase struct {
	XMLName   xml.Name        `xml:"testcase"`
	Name      string          `xml:"name,attr"`
	Skipped   TestCaseSkipped `xml:"skipped"`
	Failure   string          `xml:"failure"`
	SystemOut string          `xml:"system-out"`
}

func (tc *TestCase) IsSkipped() bool {
	return tc.Skipped.Message != ""
}

func (tc *TestCase) IsFailure() bool {
	return tc.Failure != ""
}

func (tc *TestCase) IsPassed() bool {
	return !tc.IsFailure()
}

func (tc *TestCase) Ignore() bool {
	_, ok := ignoreTestCases[tc.Name]
	return ok
}

type TestProperty struct {
	XMLName xml.Name `xml:"property"`
	Name    string   `xml:"name,attr"`
	Value   string   `xml:"value,attr"`
}

type TestSuite struct {
	XMLName  xml.Name `xml:"testsuite"`
	Name     string   `xml:"name,attr"`
	Tests    int      `xml:"tests,attr"`
	Skipped  int      `xml:"skipped,attr"`
	Failures int      `xml:"failures,attr"`
	Time     int      `xml:"time,attr"`

	Property TestProperty `xml:"property"`

	TestCases []TestCase `xml:"testcase"`
}
