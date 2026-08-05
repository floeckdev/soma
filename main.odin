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

// TODO(oskar): implement dependency rebuild stuff
Page :: struct {
	info: os.File_Info,			
	category: string,
	is_index: bool
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
	Command: init 
	Initialise site with default content
*/

init :: proc(name: string) {
	if os.exists(name) {
		fmt.printfln("soma (error): directory `%s` already exists", name)
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
		fmt.printfln("dirs: %v", directory)
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
	Command: build
	Clears /build, builds html from parsed markdown files,
	does other stuff too
*/

build :: proc(dev_mode: bool = false) {
	build_alloc := context.allocator

	root_dir, _ := os.getwd(context.allocator)
	build_dir := strings.concatenate({root_dir, "/build"}, build_alloc)
	os.remove_all(build_dir)

	// Discovery
	discovered_content := _discover_content(root_dir, build_alloc)

	for page in discovered_content {
		fmt.printfln("page: %v", page.info)
	}

}

_discover_content :: proc(root_dir: string, allocator: runtime.Allocator) -> [dynamic]Page {
	discovered := make([dynamic]Page, allocator)

	w := os.walker_create_path(root_dir)
	defer os.walker_destroy(&w)
	
	for file in os.walker_walk(&w) {
		if (file.type != .Regular) || (filepath.ext(file.name) != ".md"){
			// Skip dirs & non-md files
			continue
		}
		if (strings.has_prefix(file.fullpath, strings.concatenate({root_dir, "/build"}, allocator))) {
			// Skip /build
			continue
		}

		// /home/ofloeck/Git/soma/soma-test/projects/index.md
		parent_dir := filepath.dir(file.fullpath)
		is_in_root := parent_dir == root_dir
		category := "" if is_in_root else filepath.base(parent_dir)

		fmt.printfln("%v, %v, %v", parent_dir, is_in_root, category)

		append(&discovered, Page {
			info = file,
			category = category,
			is_index = file.name == "index.md"
		})

	}

	return discovered
}

_process_content :: proc() {
	// TODO: for each non-draft *.md, classify index vs item, then build_page.
	fmt.printfln("soma: process_category_dir %s — TODO")
}

_collect_items :: proc() {
	// TODO: parse every non-draft, non-index *.md into a context map, attach a
	// "url" key, then SORT here in Odin (newest first / by rank) so templates
	// only ever iterate already-ordered data.
	return
}

_build_page :: proc() {
	// TODO: parse_md -> build context (+ items for Cat_Index) -> render -> write
	// to build/ with pretty-URL folder layout (post -> post/index.html).
	fmt.printfln("soma: build_page %s — TODO")
}


/*
	Parse markdown and frontmatter
*/

parse_md :: proc(file_path: string) -> () {
	
	return 
}

split_frontmatter :: proc(source: string) {
	return
}

parse_frontmatter :: proc(text: string) {
	return
}

frontmatter_to_context :: proc() {
	return
}

markdown_append_chunk :: proc "c" (text: [^]u8, size: c.uint, userdata: rawptr) {
	context = runtime.default_context()
	builder := cast(^strings.Builder)userdata
	chunk := string(text[:int(size)])
	strings.write_string(builder, chunk)
}

markdown_to_html :: proc(markdown_source: string) -> string {
	//builder := strings.builder_make()
	input := transmute([]u8)markdown_source

	// md_html(
	// 	raw_data(input),
	// 	c.uint(len(input)),
	// 	markdown_append_chunk,
	// 	&builder,
	// 	MARKDOWN_PARSER_FLAGS,
	// 	0,
	// )

	return "" //strings.to_string(builder)
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

parse_iso_date :: proc(text: string) -> (Date, bool) {
	// TODO: parse "YYYY-MM-DD".
	return Date{}, false
}

MONTH_NAMES := [13]string {
	"", "January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
}

WEEKDAY_NAMES := [7]string {
	"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
}

weekday_index :: proc(date: Date) -> u16 {
	// Sakamoto's method
	month_offsets := [12]u16{0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4}
	year := date.year
	if date.month < 3 {
		year -= 1
	}
	return (year + year / 4 - year / 100 + year / 400 + month_offsets[date.month - 1] + date.day) % 7
}

ordinal_suffix :: proc(day: u16) -> string {
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

format_date :: proc(date: Date) -> string {
	weekday := WEEKDAY_NAMES[weekday_index(date)]
	month := MONTH_NAMES[date.month]
	suffix := ordinal_suffix(date.day)
	// "Sunday, 19th January, 2026".
	return fmt.tprintf("%s, %d%s %s, %d", weekday, date.day, suffix, month, date.year)
}
