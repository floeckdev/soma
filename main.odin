/*
	File: main.odin
	The driver for soma, a static site generator
*/

#+vet explicit-allocators
#+feature dynamic-literals

package soma

import "core:fmt"
import "core:os"
import "core:strings"
import "core:path/filepath"
import "core:c"
import "base:runtime"
import "utils"
import "core:strconv"

foreign import md4c_html "system:md4c-html"

foreign md4c_html {
    md_html :: proc(
        input:          cstring,
        size:           c.uint,
        process_output: proc "c" (output: cstring, size: c.uint, userdata: rawptr),
        userdata:       rawptr,
        parser_flags:   c.uint,
        renderer_flags: c.uint,
    ) -> c.int ---
}

// TODO(oskar): check actual md4c.h for more options
MARKDOWN_PARSER_FLAGS :: c.uint(0x0040 | 0x0004)

Render_Context :: struct {
	//templates: [dyn]

}

Page :: struct {
	file_path: string, 					 // home/user/my-site/index.md		
	category: string,  					 // projects, ""
	is_index: bool,	   					 // true, false
	frontmatter: map[string]Frontmatter, // title: "test", rank: 1, tags: [code, stuff]
	content: string,					 // HTML parsed of raw content
	items: []Page						 // category & index pages only
}

Template :: struct {
	name: string,		// base.html, default.html, content.html
	file_path: string,	// home/user/my-site/templates/base.html
	raw: string,		// unprocessed content
	content: []Token	// lexed content
}

Parsed_Template :: struct {
	name: string,		// default.html
	extends: string,	// base.html
	nodes: []Node,		// parsed AST of template
}

Frontmatter :: union {
	string,				// supported frontmatter types
	[]string,
	int,
	bool,
	utils.Date
}

Token_Kind :: enum {
	Text,		// raw literal " <main>\n "
	Tag,		// {{ title }}
	Block		// {% block content %} {% endblock %} {% extends "base.html" %}
}

Token :: struct {
	type: Token_Kind,
	content: string
}

Node_Kind :: enum {
	Text,		// <h1>Heading</h1>
	Tag,		// {{ title }}
	For,		// {{ for item in items }}
	If,			// {{ if dev_mode }}
	Block,		// {% block content %}
	Include,	// {% include "nav.html" %}
}

Node :: struct {
	kind: Node_Kind,	// Tag
	value: string,		// title
	pipes: []string,	// {"upper", "truncate"}
	children: []Node	
}

built_ins := map[string]utils.Built_In_Function {
	"format_date" = utils.format_date,
	"uppercase" = utils.uppercase,
	"brief" = utils.brief
}

PRINT_USAGE :: "soma — a static site generator without the noise\n" +
			   "usage:\n" +
			   "  soma init <name>     scaffold a new site\n" +
			   "  soma build           renders site into build directory\n" +
			   "  soma serve [port]    serve (--dev for live reload)\n" +
			   "  soma clean           clears build directory\n"

/*
	Program entrypoint. Handles the CLI interface.
*/
main :: proc() {
	arguments := os.args
	arg_len := len(arguments)
	if arg_len < 2 {
		fmt.print(PRINT_USAGE)
		return
	}
	command := arguments[1]

	defer free_all(context.allocator)
	working_dir, _ := os.getwd(context.allocator)

	switch command {
	case "init":
		if len(arguments) < 3 {
			fmt.println("soma (error): `init` needs a site name")
			return
		}
		init(arguments[2])

	case "build":
		build(working_dir, false)

	case "serve":
		port := 8000
		dev := false
		for arg, i in arguments {
			if arg == "--dev" {
				dev = true
			}
			if arg == "--port" {
				parsed_port, ok := strconv.parse_int(arguments[i+1], 10)
				if (!ok) {
					fmt.println("soma (err): Error parsing port!")
					return
				}
				port = parsed_port
			}
		}
		serve(port, dev)

	case "clean":
		clean(working_dir)

	case:
		fmt.print(PRINT_USAGE)
	}
}


/* 
	Initialise site with default content. Creates default directories,
	then populates with some categories and default styling.
*/
init :: proc(name: string) {
	if os.exists(name) {
		fmt.printfln("soma (error): directory `%s` already exists", name)
		// TODO(oskar): || os.is_reserved_name(name)
		return
	}
	init_alloc := context.allocator

	// Scaffod directories
	directories := []string {
		name,
		strings.concatenate({name, "/templates"}, init_alloc),
		strings.concatenate({name, "/build"}, init_alloc),
		strings.concatenate({name, "/assets"}, init_alloc),
		strings.concatenate({name, "/assets", "/css"}, init_alloc),
		strings.concatenate({name, "/assets", "/fonts"}, init_alloc),
		strings.concatenate({name, "/blog"}, init_alloc),
		strings.concatenate({name, "/projects"}, init_alloc),
	}
	for directory in directories {
		os.make_directory(directory)
	}

	// Create default templates
	templates := utils.default_templates()
	templates_dir, _ := filepath.join({name, "templates"}, init_alloc)
	for file_name, contents in templates {
		path, _ := filepath.join({templates_dir, file_name}, init_alloc)
		_write_text_file(path, contents)
	}

	// Create default content
	content := utils.default_content()
	for relative_path, contents in content {
		path, _ := filepath.join({name, relative_path}, init_alloc)
		_write_text_file(path, contents)
	}

	// Copy default assets
	asset_path, _ := filepath.join({name, "assets", "css"}, init_alloc)
	ASSET_FILES := #load_directory("css")
	for a in ASSET_FILES {
		path, _ := filepath.join({asset_path, a.name}, init_alloc)
		err := os.write_entire_file_from_bytes(path, a.data)
		if (err != nil) {
			fmt.println("soma (error): Error writing asset!")
		}
	}

	// Copy default fonts
	font_path, _ := filepath.join({name, "assets", "fonts"}, init_alloc)
	FONT_FILES := #load_directory("fonts")
	for f in FONT_FILES { 
		path, _ := filepath.join({font_path, f.name}, init_alloc)
		err := os.write_entire_file_from_bytes(path, f.data) 
		if (err != nil) {
			fmt.println("soma (error): Error writing font file!")
		}
	}

	fmt.printfln("soma: new instance `%s` created", name)
	fmt.println("soma: run `soma build` then `soma serve` to get started")
}

_write_text_file :: proc(path: string, contents: string) {
	parent := filepath.dir(path)
	os.make_directory(parent)
	err := os.write_entire_file(path, transmute([]u8)contents)
	if (err != nil) {
		fmt.printfln("soma (error): could not write file %s", path)
	}
}


/*
	Clears /build, builds html from parsed markdown files,
	does other stuff too
*/
build :: proc(working_dir: string, dev_mode: bool = false) {
	build_alloc := context.allocator

	build_dir, _ := filepath.join({working_dir, "/build"}, build_alloc)
	os.remove_all(build_dir)
	os.mkdir(build_dir)

	// Process templates
	templates := _discover_templates(working_dir)
	_template_lexer(&templates)
	parsed_templates := _parse_templates(templates)
	
	final_templates := _resolve_templates(parsed_templates)
	// ^this step resolves `extends` and `include` blocks

	// Process site content
	pages := _discover_content(working_dir, build_alloc)
    _discover_items(&pages, build_alloc)

	// for template in templates {
	// 	fmt.println("----- TEMPLATE DEBUG -----")
	// 	fmt.printfln("path: %s", template.file_path)
	// 	fmt.printfln("name: %v", template.name)
	// 	fmt.printfln("tokens: %v", template.content)
	// }

	// for page in pages {
	// 	fmt.println("----- PAGE DEBUG -----")
	// 	fmt.printfln("path: %s", page.file_path)
	// 	fmt.printfln("fm: %v", page.frontmatter)
	// 	fmt.printfln("content: %v", page.content)
	// 	//fmt.printfln("pages: %v", page.items)
	// }
}


/*
	This function discovers content within the site and also validates
	to ensure it is relevant i.e. not draft, valid frontmatter
*/
_discover_content :: proc(working_dir: string, allocator: runtime.Allocator) -> [dynamic]Page {
	discovered := make([dynamic]Page, allocator)

	w := os.walker_create_path(working_dir)
	defer os.walker_destroy(&w)
	
	collect_flag := false

	for file in os.walker_walk(&w) {
		if (file.type != .Regular) || (filepath.ext(file.name) != ".md") {
			// Skip dirs & non-md files
			continue
		}
		if (strings.has_prefix(file.fullpath, strings.concatenate({working_dir, "/build"}, allocator))) {
			// Skip /build
			os.walker_skip_dir(&w)
			continue
		}
		if (strings.has_prefix(file.name, "_")) {
			// Skip drafts i.e. _post.md
			fmt.printfln("soma (info): Skipping draft %v", file.name)
			continue
		}

		parent_dir := filepath.dir(file.fullpath)
		is_in_root := parent_dir == working_dir
		category := "" if is_in_root else filepath.base(parent_dir)

		// Frontmatter & body splitting
		raw, _ := os.read_entire_file_from_path(file.fullpath, allocator)
		content := string(raw)

		// TODO(oskar): Maybe we strings.scrub here?
		split_content := strings.split_n(content, "---", 3, allocator)
		if len(split_content) != 3 {
			relative_path, error := filepath.rel(working_dir, file.fullpath, allocator)
			fmt.printfln("soma (err): invalid frontmatter in `%s`",
						 relative_path)
			continue
		}

		append(&discovered, Page {
			file_path = strings.clone(file.fullpath, allocator),
			category = strings.clone(category, allocator),
			is_index = strings.clone(file.name, allocator) == "index.md",
			frontmatter = _extract_frontmatter(split_content[1], allocator),
			content = _markdown_to_html(split_content[2], allocator)
		})
	}

	return discovered
}


/*
	Appends the appropriate items to pages that need it.
	These incude only pages that are both an index.md AND
	belong to a category i.e. `blog/index.md`
*/
_discover_items :: proc(pages: ^[dynamic]Page, allocator: runtime.Allocator) {
	for &page in pages {
		found := make([dynamic]Page, allocator)
		if page.is_index && page.category != "" {
			// This page needs items
			for candidate in pages {
				cat_match := candidate.category == page.category
				not_self := candidate.file_path != page.file_path
				if (cat_match && not_self) {
					append(&found, candidate)
				}
			}
		}
		page.items = found[:]
	}
}

_extract_frontmatter :: proc(frontmatter: string, allocator: runtime.Allocator) -> map[string]Frontmatter {
	parsed := make(map[string]Frontmatter, allocator)

	// title: "Home"\n 
	// template: "default"\n
	// tags: [odin, test]\n
	raw := strings.split_lines(frontmatter, allocator)

	for line in raw {
		if strings.trim_space(line) == "" {
			continue
		}

		key, _, value := strings.partition(line, ":")
		key = strings.trim_space(key)
		value = strings.trim_space(value) // e.g. "title", [c, c++], true, 1, Date 2015-09-11
		parsed[key] = _parse_value(value, allocator)
	}

	return parsed
}


/*
	Where an individual frontmatter item is parsed.
	i.e. any of "My Post", [c, c++], true, 1, 2015-09-11
	See `Frontmatter` for supported types
*/
_parse_value :: proc(value: string, allocator: runtime.Allocator) -> Frontmatter {
    if strings.has_prefix(value, "[") {
        inner := value[1:len(value)-1]
        parts := strings.split(inner, ",", allocator)
		result := make([dynamic]string, 0, len(parts), allocator)
        for part, i in parts {
			trimmed := strings.trim_space(part)
			if (len(trimmed) == 0) {
				continue
			}
            append(&result, trimmed)
        }
        return result[:]
    }

    if value == "true" { 
		return true  
	}
    if value == "false" { 
		return false 
	}

    if strings.contains(value, "-") {
        date, ok := utils._parse_iso_date(value)
        if ok { 
			return date 
		}
    }

    number, ok := strconv.parse_int(value, 10)
    if ok { 
		return number 
	}

    return strings.trim(value, "\"")
}


/*
	Resolves any possible inheritence requirements of templates.
*/
_resolve_templates :: proc(templates: [dynamic]Parsed_Template) -> [dynamic]Parsed_Template {
	resolved := make([dynamic]Parsed_Template, context.allocator)
	
	for template in templates {
		
		// we have template
		// this template has an AST of []Nodes AND extends

	}
	
	return resolved
}


/*
	Discover site templates and tokenize.
*/
_discover_templates :: proc(working_dir: string) -> [dynamic]Template {
	template_dir, _ := filepath.join({working_dir, "templates"}, context.allocator)
	templates := make([dynamic]Template, context.allocator)

	w := os.walker_create_path(template_dir)
	defer os.walker_destroy(&w)

	for file in os.walker_walk(&w) {
		if filepath.ext(file.name) != ".html" {
			continue
		}
		read, _ := os.read_entire_file_from_path(file.fullpath, context.allocator)

		append(&templates, Template{
			file_path = strings.clone(file.fullpath, context.allocator),
			name = strings.clone(file.name, context.allocator),
			raw = string(read)
		})
	}
	return templates
}


/*
	Lexes the template into discrete sections the parser can use.
	i.e. <h1> {{ heading }} </h1>
	RAW: "<h1> "
	VAR: "heading"
	RAW: " </h1>"
*/
_template_lexer :: proc(templates: ^[dynamic]Template) {
	for &file in templates {
		template := file.raw
		tokens := make([dynamic]Token, context.allocator)
		cursor := 0

		for cursor < len(template) {
			tag_start := strings.index(template[cursor:], "{{")
			block_start := strings.index(template[cursor:], "{%")

			// No more Tags or Blocks
			if tag_start == -1 && block_start == -1 {
				append(&tokens, Token {
					type = .Text,
					content = template[cursor:]
				})
				break
			}

			next := tag_start < block_start ? tag_start : block_start
			
			// TODO(oskar): this all looks so bad. Fix later
			if tag_start == -1 {
				next = block_start
			}
			if block_start == -1 {
				next = tag_start
			}

			next = next + cursor
			content := template[cursor:next]

			// If we have raw content, process it
			if len(content) > 0 {
				append(&tokens, Token {
					type = .Text,
					content = content
				})
				cursor = next
				continue
			} 

			// Process blocks and tags
			if template[cursor] == '{' && template[cursor+1] == '%' {
				end := strings.index(template[cursor:], "%}")
				inner := strings.trim_space(template[cursor+2:cursor+end])
				append(&tokens, Token {
					type = .Block,
					content = inner
				})
				cursor = cursor + end + 2
			} else {
				end := strings.index(template[cursor:], "}}")
				inner := strings.trim_space(template[cursor+2:cursor+end])
				append(&tokens, Token {
					type = .Tag,
					content = inner
				})
				cursor = cursor + end + 2
			}
		}

		file.content = tokens[:]
	}
}


/*
	Parses templates lexed content into an AST.
*/
_parse_templates :: proc(templates: [dynamic]Template) -> [dynamic]Parsed_Template {
	parsed := make([dynamic]Parsed_Template, context.allocator)
	for template in templates {
		nodes, extends_target, _ := _parse_nodes(template.content)
		fmt.printfln("--- AST DEBUG ---")
		fmt.printfln("name: %v", template.name)
		fmt.printfln("extends: %v", extends_target)
		fmt.printfln("nodes: %v", nodes)
		append(&parsed, Parsed_Template {
			name = template.name,
			extends = extends_target,
			nodes = nodes
		})
	}
	return parsed
}

/*
	Performs actual conversion of lex'ed tokens to AST.
*/
_parse_nodes :: proc(tokens: []Token) -> ([]Node, string, int) {
	nodes := make([dynamic]Node, context.allocator)
	extends_target := ""
	cursor := 0

	for cursor < len(tokens) {
		token := tokens[cursor]

		// .Text `<h1>Heading</h1>`
		if token.type == .Text {
			append(&nodes, Node {
				kind = .Text,
				value = token.content
			})
			cursor = cursor + 1
			continue
		}

		// .Tag `title | upper | truncate`
		if token.type == .Tag {
			parts := strings.split(token.content, "|", context.allocator)
			var := strings.trim_space(parts[0])

			pipes := make([dynamic]string, 0, len(parts) - 1, context.allocator)
			for part in parts[1:] {
				pipe := strings.trim_space(part)
				if len(pipe) == 0 {
					continue
				}
				append(&pipes, pipe)
			}

			append(&nodes, Node {
				kind = .Tag,
				value = var,
				pipes = pipes[:]
			})
			cursor = cursor + 1
			continue
		}

		// .Block `for, if, extends & block`
		// TODO(oskar): `include` in blocks
		if token.type == .Block {
			block_type, _, arg := strings.partition(token.content, " ")
			block_type = strings.trim_space(block_type)
			arg = strings.trim_space(arg)

			switch block_type {
				case "extends":
					extends_target = strings.trim(arg, "\"")
					cursor = cursor + 1
				
				case "block", "if", "for":
					node_kind := Node_Kind.Block
					if block_type == "if" { 
						node_kind = .If 
					}
					if block_type == "for" {
						node_kind = .For
					}

					child_nodes, _, consumed := _parse_nodes(tokens[cursor+1:])
					append(&nodes, Node {
						kind = node_kind,
						value = arg,
						children = child_nodes
					})
					cursor = cursor + consumed + 2

				case "endblock", "endif", "endfor":
					return nodes[:], extends_target, cursor
					
				case:
					fmt.printfln("soma (warn): unknown block type `%s`", block_type)
					cursor = cursor + 1
			}
		}
	}
	return nodes[:], extends_target, cursor
}

_markdown_to_html :: proc(markdown_source: string, allocator: runtime.Allocator) -> string {
	builder := strings.builder_make(allocator)
	input := transmute([]u8)markdown_source

	md_html(
		cast(cstring)raw_data(input),
		c.uint(len(input)),
		_md4c_callback,
		&builder,
		MARKDOWN_PARSER_FLAGS,
		0,
	)

	return strings.to_string(builder)
}

_md4c_callback :: proc "c" (output: cstring, size: c.uint, userdata: rawptr) {
	// Due to nature of foregin C we need to declare context again?
	// TODO(oskar): research this ^
	context = runtime.default_context()
	builder := cast(^strings.Builder)userdata
	chunk := string(output)
	strings.write_string(builder, chunk[:size])
}


/*
	Command: serve
	Flag(s): port, dev
	Serve site at specific port. Can be in dev mode
	which supports live reload
*/
serve :: proc(port: int, dev: bool) {
	utils.listen_and_serve(port)
}


/*
	Command: clean
	Cleans the specified build directory
*/
clean :: proc(working_dir: string) {
	path := strings.concatenate({working_dir, "/build"}, context.allocator)

	err := os.remove_all(path)
	if (err != nil) {
		fmt.printfln("soma (err): Error cleaning! %v", err)
		return
	}
	fmt.printfln("soma: cleaned %s", path)
}


