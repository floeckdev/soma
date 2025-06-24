/* 
	main.go: CLI Interface
*/

package main

import (
	"fmt"
	"os"
	"time"

	"github.com/spf13/cobra"
)

func main() {
	var rootCmd = &cobra.Command{
		Use:   "soma",
		Short: "A simple static site generator",
		Run: func(cmd *cobra.Command, args []string) {
			cmd.Help()
		},
	}

	// Init command
	var initCmd = &cobra.Command{
		Use:   "init",
		Short: "Initialise a new site",
		Run: func(cmd *cobra.Command, args []string) {
			initSite()
		},
	}

	// Build command
	var buildCmd = &cobra.Command{
		Use:   "build",
		Short: "Build the site",
		Run: func(cmd *cobra.Command, args []string) {
			buildSite()
		},
	}

	// Serve command (placeholder for now)
	var serveCmd = &cobra.Command{
		Use:   "serve",
		Short: "Start development server",
		Run: func(cmd *cobra.Command, args []string) {
			buildSite()
			fmt.Println("Starting server at http://localhost:3000")
			fmt.Println("(Server not implemented yet - just build for now)")
		},
	}

	// New post command
	var newCmd = &cobra.Command{
		Use:   "new [title]",
		Short: "Create a new post",
		Args:  cobra.ExactArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			createPost(args[0])
		},
	}

	rootCmd.AddCommand(initCmd, buildCmd, serveCmd, newCmd)
	rootCmd.Execute()
}

func initSite() {
	fmt.Println("Initializing new site...")

	// Create directories
	dirs := []string{"content", "static", "public"}
	for _, dir := range dirs {
		os.MkdirAll(dir, 0755)
		fmt.Printf("Created: %s/\n", dir)
	}

	// Create sample post
	samplePost := `---
title: Welcome to My Site
date: ` + time.Now().Format("2006-01-02") + `
---

# Welcome!

This is your first post. You can:

- Edit this file: content/welcome.md
- Create new posts: mysite new "Post Title" 
- Build your site: mysite build
- View at: public/index.html

Happy blogging!`

	os.WriteFile("content/welcome.md", []byte(samplePost), 0644)
	fmt.Println("Created: content/welcome.md")

	// Create basic CSS
	css := `body {
    font-family: system-ui, sans-serif;
    max-width: 800px;
    margin: 0 auto;
    padding: 20px;
    line-height: 1.6;
}
h1 { color: #333; }
.post { margin-bottom: 2rem; }
.meta { color: #666; font-size: 0.9em; }
a { color: #0066cc; text-decoration: none; }
a:hover { text-decoration: underline; }`

	os.WriteFile("static/style.css", []byte(css), 0644)
	fmt.Println("Created: static/style.css")

	fmt.Println("\nSite initialised! Run 'soma build' to generate your site.")
}

