/*
    File: utils/templates.odin
    Default content for new sites.
*/

package utils

BASE_TEMPLATE :: `<!DOCTYPE html>
<html lang="en">
<head>
    <meta name="build-hash" content="{{ build_hash }}">
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ title }}</title>
    <link rel="stylesheet" href="/assets/css/app.css">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css">
</head>
<body class="font-serif max-w-2xl mx-auto px-6 py-10 text-stone-800">
    <nav class="flex gap-4 mb-10 text-sm">
        <a href="/" class="hover:underline">Home</a>
        <a href="/blog/" class="hover:underline">Blog</a>
        <a href="/projects/" class="hover:underline">Projects</a>
        <a href="/about" class="hover:underline">About</a>
    </nav>
    <main class="prose">
        {% block content %}{% endblock %}
    </main>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
    <script>hljs.highlightAll();</script>
    {% if dev_mode %}
    <script>{{ inject_script | safe }}</script>
    {% endif %}
</body>
</html>`

DEFAULT_TEMPLATE :: `{% extends "base.html" %}
{% block content %}
<h1 class="text-3xl font-bold mb-6">{{ title }}</h1>
{{ content | safe }}
{% endblock %}`

CATEGORY_TEMPLATE :: `{% extends "base.html" %}
{% block content %}
<h1 class="text-3xl font-bold mb-6">{{ title }}</h1>
{{ content | safe }}
<h2 class="text-2xl font-semibold mt-10 mb-4">Recent Content</h2>
<ul class="space-y-2">
{% for item in items %}
    <li><a href="{{ item.url }}" class="hover:underline">{{ item.title }}</a> — {{ item.date | format_date }}</li>
{% endfor %}
</ul>
{% endblock %}`

CONTENT_TEMPLATE :: `{% extends "base.html" %}
{% block content %}
<h1 class="text-3xl font-bold mb-2">{{ title }}</h1>
<p class="text-sm text-stone-500 mb-6"><time datetime="{{ date }}">{{ date | format_date }}</time></p>
{{ content | safe }}
{% endblock %}`

default_templates :: proc() -> map[string]string {
    templates := make(map[string]string, context.allocator)

    templates["base.html"]     = BASE_TEMPLATE
    templates["default.html"]  = DEFAULT_TEMPLATE
    templates["category.html"] = CATEGORY_TEMPLATE
    templates["content.html"]  = CONTENT_TEMPLATE  

    return templates
}

default_content :: proc() -> map[string]string {
	default_content := make(map[string]string, context.allocator)

	default_content["index.md"] = "---\ntitle: \"Home\"\ntemplate: \"default\"\n---\n\n# Welcome\n\nNew soma site.\n"
	default_content["about.md"] = "---\ntitle: \"About\"\ntemplate: \"default\"\n---\n\nAbout this site.\n"
	default_content["blog/index.md"] = "---\ntitle: \"Blog\"\ntemplate: \"category\"\n---\n\nPosts.\n"
	default_content["projects/index.md"] = "---\ntitle: \"Projects\"\ntemplate: \"category\"\n---\n\nThings I built.\n"

	return default_content
}
