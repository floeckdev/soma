/*
	File: main.odin
	The driver for soma, a static site generator
*/

#+vet explicit-allocators

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

Page :: struct {
	file_path: string, // home/user/my-site/index.md		
	category: string,  // projects or ""
	is_index: bool	   // true or false
}

Parsed_Page :: struct {
    source:   Page,								
    frontmatter: map[string]Frontmatter_Value,	// title: "test", rank: 1, tags: [code, stuff]
    body: string								// "body of post"
}

Rendered_Page :: struct {
    output_path: string,
    html:        string,
}

Frontmatter_Value :: union {
	string,
	[]string,
	int,
	bool,
	Date
}

Date :: struct {
	day: u16,
	month: u16,
	year: u16
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

	switch command {
	case "init":
		if len(arguments) < 3 {
			fmt.println("soma (error): `init` needs a site name")
			return
		}
		init(arguments[2])

	case "build":
		build(false)

	case "serve":
		port := 8000
		dev := false
		for i := 0; i < arg_len; i+=1 {
			if arguments[i] == "--dev" {
				dev = true
			}
			if arguments[i] == "--port" {
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
		clean()

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
	defer free_all(init_alloc)

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
build :: proc(dev_mode: bool = false) {
	build_alloc := context.allocator
	defer free_all(build_alloc)

	root_dir, _ := os.getwd(build_alloc)
	build_dir, _ := filepath.join({root_dir, "/build"}, build_alloc)
	os.remove_all(build_dir)

	pages := _discover_content(root_dir, build_alloc)
	parsed_pages := _parse_all(pages, build_alloc)
    rendered_pages := _render_all(parsed_pages, build_alloc)
    _write_all(rendered_pages, build_dir, build_alloc)

	for page in parsed_pages {
		fmt.printfln("path: %s", page.source.file_path)
		fmt.printfln("fm: %v", page.frontmatter)
	}


}

_discover_content :: proc(root_dir: string, allocator: runtime.Allocator) -> [dynamic]Page {
	discovered := make([dynamic]Page, allocator)

	w := os.walker_create_path(root_dir)
	defer os.walker_destroy(&w)
	
	for file in os.walker_walk(&w) {
		if (file.type != .Regular) || (filepath.ext(file.name) != ".md") {
			// Skip dirs & non-md files
			continue
		}
		if (strings.has_prefix(file.fullpath, strings.concatenate({root_dir, "/build"}, allocator))) {
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
		is_in_root := parent_dir == root_dir
		category := "" if is_in_root else filepath.base(parent_dir)

		append(&discovered, Page {
			file_path = strings.clone(file.fullpath, allocator),
			category = strings.clone(category, allocator),
			is_index = strings.clone(file.name, allocator) == "index.md"
		})
	}

	return discovered
}

/*
	Extract the frontmatter and markdown body from raw files
*/
_parse_all :: proc(pages: [dynamic]Page, allocator: runtime.Allocator) -> [dynamic]Parsed_Page {
	parsed := make([dynamic]Parsed_Page, allocator)

	for current_page in pages {
		raw, _ := os.read_entire_file_from_path(current_page.file_path, allocator)
		content := string(raw)

		// TODO(oskar): Maybe we strings.scrub here?
		split_content := strings.split_n(content, "---", 3, allocator)
		if len(split_content) != 3 {
			fmt.printfln("soma (error): invalid frontmatter in `%s`",
						current_page.file_path)
			continue
		}

		append(&parsed, Parsed_Page {
			source = current_page,
			frontmatter = _extract_frontmatter(split_content[1], allocator),
			body = split_content[2]
		})

	}

	return parsed
}

_extract_frontmatter :: proc(frontmatter: string, allocator: runtime.Allocator) -> map[string]Frontmatter_Value {
	parsed := make(map[string]Frontmatter_Value, allocator)

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
	Where an individual frontmatter entity is parsed.
	i.e. any of "My Post", [c, c++], true, 1, 2015-09-11
	See `Frontmatter_Value` for supported types
*/
_parse_value :: proc(value: string, allocator: runtime.Allocator) -> Frontmatter_Value {
    if strings.has_prefix(value, "[") {
        inner := value[1:len(value)-1]
        items := strings.split(inner, ",", allocator)
        for item, i in items {
            items[i] = strings.trim_space(item)
        }
        return items
    }

    if value == "true" { 
		return true  
	}
    if value == "false" { 
		return false 
	}

    if strings.contains(value, "-") {
        date, ok := _parse_iso_date(value)
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
	Takes our parsed pages and renders as HTML
*/
_render_all :: proc(parsed_pages: [dynamic]Parsed_Page, allocator: runtime.Allocator) -> [dynamic]Rendered_Page {

	return nil
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
    // your implementation
}

_write_all :: proc(rendered_pages: [dynamic]Rendered_Page, build_dir: string, allocator: runtime.Allocator) {
	// site/item.md 		-> site/build/item/index.html		// cat 0, root 0
	// site/index.md 		-> site/build/index.html			// cat 0, root 1
	// site/cat/index.md	-> site/build/cat/index.html		// cat 1, root 1
	// site/cat/post.md		-> site/build/cat/post/index.html	// cat 1, root 0


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
clean :: proc() {
	clean_alloc := context.allocator
	defer free_all(clean_alloc)

	curr_dir, _ := os.getwd(clean_alloc)

	path := strings.concatenate({curr_dir, "/build"}, clean_alloc)

	err := os.remove_all(path)
	if (err != nil) {
		fmt.printfln("soma (err): Error cleaning! %v", err)
		return
	}
	fmt.printfln("soma: cleaned %s", path)
}


/*
	Date helpers
*/
MONTH_NAMES := [13]string {
	"", "January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
}

WEEKDAY_NAMES := [7]string {
	"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
}

_parse_iso_date :: proc(text: string) -> (Date, bool) {
	// TODO: parse "YYYY-MM-DD".
	return Date{}, false
}

_weekday_index :: proc(date: Date) -> u16 {
	// Sakamoto's method
	month_offsets := [12]u16{0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4}
	year := date.year
	if date.month < 3 {
		year -= 1
	}
	return (year + year / 4 - year / 100 + year / 400 + month_offsets[date.month - 1] + date.day) % 7
}

_ordinal_suffix :: proc(day: u16) -> string {
	if 11 <= day && day <= 13 {
		return "th"
	}
	switch day % 10 {
	case 1:
		return "st"
	case 2:
		return "nd"
	case 3:
		return "rd"
	case:
		return "th"
	}
}

_format_date :: proc(date: Date) -> string {
	weekday := WEEKDAY_NAMES[_weekday_index(date)]
	month := MONTH_NAMES[date.month]
	suffix := _ordinal_suffix(date.day)
	// "Sunday, 19th January, 2026".
	return fmt.tprintf("%s, %d%s %s, %d", weekday, date.day, suffix, month, date.year)
}
