// Healthcheck for the baked-in library server.
// With no arguments it succeeds only when PROPFIND / returns 207.
// `healthcheck range` is the image-build check that a byte range of the fixture file is served.
package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

func main() {
	client := &http.Client{Timeout: 3 * time.Second}
	if len(os.Args) > 1 && os.Args[1] == "range" {
		rangeCheck(client)
		return
	}
	propfind(client)
}

func propfind(client *http.Client) {
	req, err := http.NewRequest("PROPFIND", "http://127.0.0.1/", nil)
	if err != nil {
		fail("%v", err)
	}
	req.Header.Set("Depth", "0")
	resp, err := client.Do(req)
	if err != nil {
		fail("%v", err)
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	if resp.StatusCode != http.StatusMultiStatus {
		fail("PROPFIND / returned %s", resp.Status)
	}
}

func rangeCheck(client *http.Client) {
	req, err := http.NewRequest(http.MethodGet, "http://127.0.0.1/Movies/demo.txt", nil)
	if err != nil {
		fail("%v", err)
	}
	req.Header.Set("Range", "bytes=0-5")
	resp, err := client.Do(req)
	if err != nil {
		fail("%v", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 32))
	if err != nil {
		fail("%v", err)
	}
	if resp.StatusCode != http.StatusPartialContent || string(body) != "sample" {
		fail("range GET returned %s body %q", resp.Status, body)
	}
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
