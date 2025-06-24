/* 
	parser.go: Markdown processing
*/

package main

import (
	"html/template"
	"path/filepath"
	"strings"
	"time"

	"github.com/gomarkdown/markdown"
	"github.com/gomarkdown/markdown/html"
	"github.com/gomarkdown/markdown/parser"
)

func parseMarkdown(content, path string) Post {
	post := Post{}

	// Simple frontmatter parsing
	if strings.HasPrefix(content, "---\n") {
		parts := strings.SplitN(content, "\n---\n", 2)
		if len(parts) == 2 {
			// Extract title and date from frontmatter
			lines := strings.Split(parts[0], "\n")
			for _, line := range lines {
				if strings.HasPrefix(line, "title:") {
					post.Title = strings.TrimSpace(strings.TrimPrefix(line, "title:"))
				}
				if strings.HasPrefix(line, "date:") {
					post.Date = strings.TrimSpace(strings.TrimPrefix(line, "date:"))
				}
			}
			content = parts[1]
		}
	}

	// Generate slug from filename
	filename := filepath.Base(path)
	post.Slug = strings.TrimSuffix(filename, ".md")

	// Default title if not set
	if post.Title == "" {
		post.Title = strings.ReplaceAll(post.Slug, "-", " ")
	}

	// Default date if not set
	if post.Date == "" {
		post.Date = time.Now().Format("2006-01-02")
	}

	// Convert markdown to HTML
	p := parser.NewWithExtensions(parser.CommonExtensions | parser.AutoHeadingIDs)
	renderer := html.NewRenderer(html.RendererOptions{
		Flags: html.CommonFlags | html.HrefTargetBlank,
	})
	htmlBytes := markdown.ToHTML([]byte(content), p, renderer)
	post.Content = template.HTML(htmlBytes)

	// Generate excerpt (first 100 chars of clean text)
	text := cleanMarkdown(content)
	if len(text) > 100 {
		post.Excerpt = text[:100] + "..."
	} else {
		post.Excerpt = text
	}

	return post
}

func cleanMarkdown(content string) string {
	// Remove common markdown formatting for excerpts
	text := strings.ReplaceAll(content, "#", "")
	text = strings.ReplaceAll(text, "*", "")
	text = strings.ReplaceAll(text, "_", "")
	text = strings.ReplaceAll(text, "`", "")
	
	// Remove extra whitespace
	fields := strings.Fields(text)
	return strings.Join(fields, " ")
}