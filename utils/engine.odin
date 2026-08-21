/*
    File: utils/engine.odin
    A simple template engine for soma.
*/

package utils

import "core:strings"
import "core:fmt"

Template_Value :: union {
    string,                 // "title"  →  "Projects"
    []map[string]string     // "items"  →  [{"url": "/foo", "title": "Foo"}] 
}

Template_Context :: map[string]Template_Value

/*
    Replace all {{ key }} occurrences in the template with their
    corresponding string values from the context.
    Ignores keys whose value is a loop list, those are handled separately.
*/
substitute_variables :: proc(template: string, context2: Template_Context, allocator := context.allocator,) -> string {
    result := strings.clone(template, allocator)

    for key, value in context2 {
        string_value, is_string := value.(string)
        if !is_string {
            continue
        }
        placeholder := fmt.aprintf("{{{{ %s }}}}", key, allocator = allocator)
        result, _ = strings.replace_all(result, placeholder, string_value, allocator)
    }

    return result
}

