/* 
    templates.go: HTML templates
*/

package main

import "html/template"

var indexTemplate = template.Must(template.New("index").Parse(`<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{.SiteTitle}}</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <header>
        <h1>{{.SiteTitle}}</h1>
        <p>Welcome to my portfolio site</p>
    </header>
    
    <main>
        {{if .Posts}}
            {{range .Posts}}
            <article class="post">
                <h2><a href="{{.Slug}}.html">{{.Title}}</a></h2>
                <p class="meta">{{.Date}}</p>
                <p>{{.Excerpt}}</p>
            </article>
            {{end}}
        {{else}}
            <p>No posts yet. Create one with: <code>mysite new "My First Post"</code></p>
        {{end}}
    </main>
</body>
</html>`))

var postTemplate = template.Must(template.New("post").Parse(`<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{.Post.Title}} - {{.SiteTitle}}</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <header>
        <h1><a href="index.html">{{.SiteTitle}}</a></h1>
    </header>
    
    <main>
        <article>
            <h1>{{.Post.Title}}</h1>
            <p class="meta">{{.Post.Date}}</p>
            {{.Post.Content}}
        </article>
        
        <nav style="margin-top: 2rem; padding-top: 1rem; border-top: 1px solid #eee;">
            <a href="index.html">← Back to all posts</a>
        </nav>
    </main>
</body>
</html>`))
