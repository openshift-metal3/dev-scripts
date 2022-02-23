package jobs

import (
	"net/http"
	"regexp"

	"golang.org/x/net/html"
)

type HtmlScraper struct {
	url     string
	pattern string
}

func NewHtmlScraper(url string, pattern string) *HtmlScraper {
	return &HtmlScraper{
		url:     url,
		pattern: pattern,
	}
}

func (h *HtmlScraper) Get() (res []string, err error) {
	r, err := http.Get(h.url)
	if err != nil {
		return nil, err
	}
	defer r.Body.Close()

	z := html.NewTokenizer(r.Body)
	for {
		tokenType := z.Next()

		if tokenType == html.ErrorToken {
			break
		}
		if tokenType != html.StartTagToken {
			continue
		}

		token := z.Token()
		if token.Data != "a" {
			continue
		}

		if len(token.Attr) == 0 || token.Attr[0].Key != "href" {
			continue
		}

		re := regexp.MustCompile(h.pattern)
		matches := re.FindStringSubmatch(token.Attr[0].Val)
		if matches == nil {
			continue
		}

		res = append(res, matches[1])
	}

	return res, nil
}
