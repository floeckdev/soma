/*
	File: main.odin
	The driver for soma, a static site generator
*/

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

	scaffold_directories(name)
	create_default_templates(_join_path({name, "templates"}))
	create_default_content(name)
	copy_default_assets(_join_path({name, "assets", "css"}))
	copy_default_fonts(_join_path({name, "assets", "fonts"}))

	fmt.printfln("soma: new instance `%s` created", name)
	fmt.println("soma: run `soma build` then `soma serve` to get started")
}

scaffold_directories :: proc(name: string) {
	directories := []string {
		name,
		_join_path({name, "templates"}),
		_join_path({name, "build"}),
		_join_path({name, "assets"}),
		_join_path({name, "assets", "css"}),
		_join_path({name, "assets", "fonts"}),
		_join_path({name, "blog"}),
		_join_path({name, "projects"}),
	}
	for directory in directories {
		os.make_directory(directory)
	}
}

create_default_templates :: proc(templates_dir: string) {
	templates := utils.default_templates()
	for file_name, contents in templates {
		_write_text_file(_join_path({templates_dir, file_name}), contents)
	}
}

create_default_content :: proc(site_path: string) {
	content := utils.default_content()
	for relative_path, contents in content {
		_write_text_file(_join_path({site_path, relative_path}), contents)
	}
}

copy_default_assets :: proc(asset_path: string) {
	ASSET_FILES := #load_directory("css")
	for a in ASSET_FILES {
		err := os.write_entire_file_from_bytes(_join_path({asset_path, a.name}), a.data)
		if (err != nil) {
			fmt.println("soma (error): Error writing asset!")
		}
	}
}

copy_default_fonts :: proc(font_path: string) {
	FONT_FILES := #load_directory("fonts")
	for f in FONT_FILES { 
		err := os.write_entire_file_from_bytes(_join_path({font_path, f.name}), f.data) 
		if (err != nil) {
			fmt.println("soma (error): Error writing font file!")
		}
	}
}

_join_path :: proc(parts: []string) -> string {
	path, err := filepath.join(parts)
	if err != nil {
		panic("soma: filepath.join allocation failed")
	}
	return path
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

	curr_dir, _ := os.getwd(context.temp_allocator)
	defer free_all(context.temp_allocator)
	os.remove_all("/build")

	// Discovery
	discovered_content := _discover_content(curr_dir)

	for page in discovered_content {
		fmt.printfln("page: %s", page.info.name)
	}

}

_discover_content :: proc(root_dir: string, allocator:= context.allocator) -> [dynamic]Page {
	discovered := make([dynamic]Page, allocator)

	w := os.walker_create_path(root_dir)
	defer os.walker_destroy(&w)
	
	// Walk the directory
	for file in os.walker_walk(&w) {
		// Skip dir & non-markdown files
		if (file.type != .Regular) || (filepath.ext(file.name) != ".md"){
			continue
		}
		// full: /home/ofloeck/Git/soma/soma-test/projects/index.md

		// join: /home/ofloeck/Git/soma/soma-test/build/index.html
		if (strings.has_prefix(file.fullpath, _join_path({root_dir, "build"}))) {
			continue
		}

		parent_dir := filepath.dir(file.fullpath)
		is_in_root := parent_dir == root_dir
		category := "" if is_in_root else filepath.base(parent_dir)

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
	builder := strings.builder_make()
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
	curr_dir, _ := os.getwd(context.temp_allocator)
	defer free_all(context.temp_allocator)

	path := _join_path({curr_dir, "/build"})

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
