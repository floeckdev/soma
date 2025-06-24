/*
	generator.go: Site building logic
*/

package main

import (
	"fmt"
	"html/template"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Simple post structure
type Post struct {
	Title   string
	Date    string
	Slug    string
	Content template.HTML
	Excerpt string
}

// Site config
var config = struct {
	SiteTitle string
	Author    string
	BaseURL   string
}{
	SiteTitle: "My Portfolio",
	Author:    "Your Name",
	BaseURL:   "",
}

func buildSite() {
	fmt.Println("Building site...")

	// Create public directory
	os.MkdirAll("public", 0755)

	// Copy static files
	copyStatic()

	// Process markdown files
	posts := processPosts()

	// Generate index
	generateIndex(posts)

	fmt.Printf("Built %d posts\n", len(posts))
}

func copyStatic() {
	if _, err := os.Stat("static"); os.IsNotExist(err) {
		return
	}

	filepath.Walk("static", func(path string, info os.FileInfo, err error) error {
		if path == "static" {
			return nil
		}

		relPath := strings.TrimPrefix(path, "static/")
		destPath := filepath.Join("public", relPath)

		if info.IsDir() {
			os.MkdirAll(destPath, info.Mode())
		} else {
			copyFile(path, destPath)
		}
		return nil
	})
}

func processPosts() []Post {
	var posts []Post

	if _, err := os.Stat("content"); os.IsNotExist(err) {
		return posts
	}

	filepath.Walk("content", func(path string, info os.FileInfo, err error) error {
		if !strings.HasSuffix(path, ".md") {
			return nil
		}

		content, err := os.ReadFile(path)
		if err != nil {
			return err
		}

		post := parseMarkdown(string(content), path)
		posts = append(posts, post)

		// Generate individual post page
		generatePost(post)

		return nil
	})

	return posts
}

func generateIndex(posts []Post) {
	file, _ := os.Create("public/index.html")
	defer file.Close()

	data := struct {
		SiteTitle string
		Posts     []Post
	}{
		SiteTitle: config.SiteTitle,
		Posts:     posts,
	}

	indexTemplate.Execute(file, data)
	fmt.Println("Generated: index.html")
}

func generatePost(post Post) {
	file, _ := os.Create(filepath.Join("public", post.Slug+".html"))
	defer file.Close()

	data := struct {
		SiteTitle string
		Post      Post
	}{
		SiteTitle: config.SiteTitle,
		Post:      post,
	}

	postTemplate.Execute(file, data)
	fmt.Printf("Generated: %s.html\n", post.Slug)
}

func createPost(title string) {
	slug := strings.ToLower(title)
	slug = strings.ReplaceAll(slug, " ", "-")
	slug = strings.ReplaceAll(slug, "'", "")

	post := fmt.Sprintf(`---
title: %s
date: %s
---

# %s

Write your post here...
`, title, time.Now().Format("2006-01-02"), title)

	filename := fmt.Sprintf("content/%s.md", slug)
	os.WriteFile(filename, []byte(post), 0644)
	fmt.Printf("Created: %s\n", filename)
}

// Helper functions
func copyFile(src, dst string) error {
	os.MkdirAll(filepath.Dir(dst), 0755)
	srcFile, _ := os.Open(src)
	defer srcFile.Close()
	dstFile, _ := os.Create(dst)
	defer dstFile.Close()
	srcFile.WriteTo(dstFile)
	return nil
}