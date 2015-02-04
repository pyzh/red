Red/System [
	Title:   "Red interpreter"
	Author:  "Nenad Rakocevic"
	File: 	 %interpreter.reds
	Tabs:	 4
	Rights:  "Copyright (C) 2011-2012 Nenad Rakocevic. All rights reserved."
	License: {
		Distributed under the Boost Software License, Version 1.0.
		See https://github.com/dockimbel/Red/blob/master/BSL-License.txt
	}
]

#define CHECK_INFIX [
	if all [
		next < end
		TYPE_OF(next) = TYPE_WORD
	][
		value: _context/get next
		if TYPE_OF(value) = TYPE_OP [
			either next = as red-word! pc [
				#if debug? = yes [if verbose > 0 [log "infix detected!"]]
				infix?: yes
			][
				if TYPE_OF(pc) = TYPE_WORD [
					left: _context/get as red-word! pc
				]
				unless all [
					TYPE_OF(pc) = TYPE_WORD
					any [
						TYPE_OF(left) = TYPE_ACTION
						TYPE_OF(left) = TYPE_NATIVE
						TYPE_OF(left) = TYPE_FUNCTION
					]
					literal-first-arg? as red-native! left	;-- a literal argument is expected
				][
					#if debug? = yes [if verbose > 0 [log "infix detected!"]]
					infix?: yes
				]
			]
		]
	]
]

#define FETCH_ARGUMENT [
	if pc >= end [fire [TO_ERROR(script no-arg) fname value]]
	
	switch TYPE_OF(value) [
		TYPE_WORD [
			#if debug? = yes [if verbose > 0 [log "evaluating argument"]]
			pc: eval-expression pc end no yes
		]
		TYPE_GET_WORD [
			#if debug? = yes [if verbose > 0 [log "fetching argument as-is"]]
			stack/push pc
			pc: pc + 1
		]
		default [
			#if debug? = yes [if verbose > 0 [log "fetching argument"]]
			switch TYPE_OF(pc) [
				TYPE_GET_WORD [
					copy-cell _context/get as red-word! pc stack/push*
				]
				TYPE_PAREN [
					either TYPE_OF(value) = TYPE_LIT_WORD [
						stack/mark-native as red-word! pc	;@@ ~paren
						eval as red-block! pc yes
						stack/unwind
					][
						stack/push pc
					]
				]
				TYPE_GET_PATH [
					eval-path pc pc + 1 end no yes yes
				]
				default [
					stack/push pc
				]
			]
			pc: pc + 1
		]
	]
]

interpreter: context [
	verbose: 0

	return-type: -1										;-- return type for routine calls
	in-func?:	 0										;@@ make it thread-safe?
	
	log: func [msg [c-string!]][
		print "eval: "
		print-line msg
	]
	
	literal-first-arg?: func [
		native 	[red-native!]
		return: [logic!]
		/local
			fun	  [red-function!]
			value [red-value!]
			tail  [red-value!]
			s	  [series!]
	][
		s: as series! either TYPE_OF(native) = TYPE_FUNCTION [
			fun: as red-function! native
			fun/spec/value
		][
			native/spec/value
		]
		value: s/offset
		tail:  s/tail
		
		while [value < tail][
			switch TYPE_OF(value) [
				TYPE_WORD 		[return no]
				TYPE_LIT_WORD	[return yes]
				default 		[0]
			]
			value: value + 1
		]
		no
	]

	preprocess-options: func [
		native 	  [red-native!]
		path	  [red-path!]
		pos		  [red-value!]
		list	  [node!]
		fname	  [red-word!]
		function? [logic!]
		return:   [node!]
		/local
			args	  [red-block!]
			value	  [red-value!]
			tail	  [red-value!]
			base	  [red-value!]
			head	  [red-value!]
			end		  [red-value!]
			saved	  [red-value!]
			word	  [red-word!]
			ref		  [red-refinement!]
			blk		  [red-value!]
			vec		  [red-vector!]
			bool	  [red-logic!]
			s		  [series!]
			ref-array [int-ptr!]
			index	  [integer!]
			offset	  [integer!]
			ref?	  [logic!]
	][
		saved: stack/top
		
		args: as red-block! stack/push*
		args/header: TYPE_BLOCK
		args/head:	 0
		args/node:	 list
		args: 		 block/clone args no				;-- copy it before modifying it

		value: block/rs-head as red-block! path
		tail:  block/rs-tail as red-block! path
		
		either function? [
			base: block/rs-head args
			end:  block/rs-tail args
			while [all [base < end TYPE_OF(base) <> TYPE_REFINEMENT]][
				base: base + 2
			]
			if base = end [fire [TO_ERROR(script bad-refines) fname as red-word! pos]]
			
			while [value < tail][
				if TYPE_OF(value) <> TYPE_WORD [
					fire [TO_ERROR(script bad-refines) fname as red-word! value]
				]
				word: as red-word! value
				head: base
				while [head < end][
					ref: as red-refinement! head
					if EQUAL_WORDS?(ref word) [
						bool: as red-logic! head + 1
						assert TYPE_OF(bool) = TYPE_LOGIC
						bool/value: true
						head: end						;-- force loop exit
					]
					head: head + 2 
				]
				value: value + 1
			]
		][
			vec: vector/clone as red-vector! (block/rs-tail args) - 1
			s: as series! native/spec/value
			base:	s/offset
			head:	base
			end:	s/tail
			offset: 0
			
			while [all [base < end TYPE_OF(base) <> TYPE_REFINEMENT]][
				switch TYPE_OF(base) [
					TYPE_WORD
					TYPE_GET_WORD
					TYPE_LIT_WORD [offset: offset + 1]
					default [0]
				]
				base: base + 1
			]
			if base = end [fire [TO_ERROR(script bad-refines) fname as red-word! pos]]
			
			s: GET_BUFFER(vec)
			ref-array: as int-ptr! s/offset
			
			while [value < tail][
				if TYPE_OF(value) <> TYPE_WORD [
					fire [TO_ERROR(script bad-refines) fname as red-word! value]
				]
				word:  as red-word! value
				head:  base
				ref?:  no
				index: 1
				
				while [head < end][
					switch TYPE_OF(head) [
						TYPE_WORD
						TYPE_GET_WORD
						TYPE_LIT_WORD [
							if ref? [
								block/rs-append args head
								blk: head + 1
								either all [
									blk < end
									TYPE_OF(blk) = TYPE_BLOCK
								][
									typeset/make-in args as red-block! blk
								][
									typeset/make-default args
								]
								offset: offset + 1
							]
						]
						TYPE_REFINEMENT [
							ref: as red-refinement! head
							either EQUAL_WORDS?(ref word) [
								ref-array/index: offset
								ref?: yes
							][
								ref?: no
							]
							index: index + 1
						]
						TYPE_SET_WORD [head: end]
						default [0]						;-- ignore other values
					]
					head: head + 1 
				]
				value: value + 1
			]
		]
		stack/top: saved
		args/node
	]
	
	preprocess-spec: func [
		native 	[red-native!]
		return: [node!]
		/local
			fun		  [red-function!]
			vec		  [red-vector!]
			list	  [red-block!]
			value	  [red-value!]
			tail	  [red-value!]
			saved	  [red-value!]
			w		  [red-word!]
			dt		  [red-datatype!]
			blk		  [red-block!]
			s		  [series!]
			routine?  [logic!]
			function? [logic!]
			ret-set?  [logic!]
			required? [logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line "cache: pre-processing function spec"]]
		
		saved:	   stack/top
		routine?:  TYPE_OF(native) = TYPE_ROUTINE
		function?: any [routine? TYPE_OF(native) = TYPE_FUNCTION]

		s: as series! either function? [
			fun:  as red-function! native
			fun/spec/value
		][
			native/spec/value
		]
		unless function? [
			vec: vector/make-at stack/push* 12 TYPE_INTEGER 4
		]
		
		list:		block/push-only* 8
		value:		s/offset
		tail:		s/tail
		required?:	yes

		while [value < tail][
			#if debug? = yes [if verbose > 0 [print-line ["cache: spec entry type: " TYPE_OF(value)]]]
			switch TYPE_OF(value) [
				TYPE_WORD
				TYPE_GET_WORD
				TYPE_LIT_WORD [
					if any [function? required?][		;@@ routine! should not be accepted here...
						block/rs-append list value
						either all [
							value + 1 < tail
							TYPE_OF(value) = TYPE_BLOCK
						][
							typeset/make-in list as red-block! value
						][
							typeset/make-default list
						]
					]
				]
				TYPE_REFINEMENT [
					required?: no
					either function? [
						block/rs-append list value
						block/rs-append list as red-value! false-value
					][
						vector/rs-append-int vec -1
					]
				]
				TYPE_SET_WORD [
					w: as red-word! value
					if words/return* <> symbol/resolve w/symbol [
						fire [TO_ERROR(script bad-func-def)	w]
					]
					blk: as red-block! value + 1
					assert TYPE_OF(blk) = TYPE_BLOCK
					either routine? [
						ret-set?: yes
						value: block/pick blk 1 null
						assert TYPE_OF(value) = TYPE_WORD
						dt: as red-datatype! _context/get as red-word! value
						assert TYPE_OF(dt) = TYPE_DATATYPE
						return-type: dt/value
					][
						block/rs-append list value
						typeset/make-in list blk
					]
				]
				default [0]								;-- ignore other values
			]
			value: value + 1
		]
		
		unless ret-set? [return-type: -1]				;-- set the default correctly in case of nested calls

		unless function? [
			block/rs-append list as red-value! none-value ;-- place-holder for argument name
			block/rs-append list as red-value! vec
		]
		stack/top: saved
		list/node
	]
	
	set-locals: func [
		fun [red-function!]
		/local
			tail  [red-value!]
			value [red-value!]
			s	  [series!]
			set?  [logic!]
	][
		s: as series! fun/spec/value
		value: s/offset
		tail:  s/tail
		set?:  no
		
		while [value < tail][
			switch TYPE_OF(value) [
				TYPE_WORD
				TYPE_GET_WORD
				TYPE_LIT_WORD [
					if set? [none/push]
				]
				TYPE_REFINEMENT [
					unless set? [set?: yes]
					logic/push false
				]
				default [0]								;-- ignore other values
			]
			value: value + 1
		]
	]
	
	eval-function: func [
		[catch]
		fun  [red-function!]
		body [red-block!]
		/local
			ctx	  [red-context!]
			saved [node!]
	][
		in-func?: in-func? + 1
		ctx: GET_CTX(fun)
		saved: ctx/values
		ctx/values: as node! stack/arguments
		eval body yes
		ctx/values: saved
		in-func?: in-func? - 1
	]
	
	exec-routine: func [
		fun	 [red-routine!]
		/local
			native [red-native!]
			arg	   [red-value!]
			bool   [red-logic!]
			int	   [red-integer!]
			s	   [series!]
			ret	   [integer!]
			count  [integer!]
			call
	][
		s: as series! fun/more/value
		native: as red-native! s/offset + 2
		call: as function! [return: [integer!]] native/code
		count: (routine/get-arity fun) - 1				;-- zero-based stack access
		
		while [count >= 0][
			arg: stack/arguments + count
			switch TYPE_OF(arg) [
				TYPE_LOGIC	 [push logic/get arg]
				TYPE_INTEGER [push integer/get arg]
				default		 [push arg]
			]
			count: count - 1
		]
		either positive? return-type [
			ret: call
			switch return-type [
				TYPE_LOGIC	[
					bool: as red-logic! stack/arguments
					bool/header: TYPE_LOGIC
					bool/value: ret <> 0
				]
				TYPE_INTEGER [
					int: as red-integer! stack/arguments
					int/header: TYPE_INTEGER
					int/value: ret
				]
				default [assert false]					;-- should never happen
			]
		][
			call
		]
	]
	
	eval-infix: func [
		value 	  [red-value!]
		pc		  [red-value!]
		end		  [red-value!]
		sub?	  [logic!]
		return:   [red-value!]
		/local
			next   [red-word!]
			left   [red-value!]
			fun	   [red-function!]
			infix? [logic!]
			op	   [red-op!]
			s	   [series!]
			call-op
	][
		stack/keep
		pc: pc + 1										;-- skip operator
		pc: eval-expression pc end yes yes				;-- eval right operand
		op: as red-op! value
		
		either op/header and body-flag <> 0 [
			node: as node! op/code
			s: as series! node/value
			fun: as red-function! s/offset + 3
			
			either TYPE_OF(fun) = TYPE_ROUTINE [
				exec-routine as red-routine! fun
			][
				set-locals fun
				eval-function fun as red-block! s/offset
			]
		][
			call-op: as function! [] op/code
			call-op
			0											;-- @@ to make compiler happy!
		]

		#if debug? = yes [
			if verbose > 0 [
				value: stack/arguments
				print-line ["eval: op return type: " TYPE_OF(value)]
			]
		]
		infix?: no
		next: as red-word! pc
		CHECK_INFIX
		if infix? [pc: eval-infix value pc end sub?]
		pc
	]
	
	eval-arguments: func [
		native 	[red-native!]
		pc		[red-value!]
		end	  	[red-value!]
		path	[red-path!]
		pos 	[red-value!]
		return: [red-value!]
		/local
			fun	  	  [red-function!]
			function? [logic!]
			routine?  [logic!]
			value	  [red-value!]
			tail	  [red-value!]
			expected  [red-value!]
			path-end  [red-value!]
			fname	  [red-word!]
			blk		  [red-block!]
			vec		  [red-vector!]
			bool	  [red-logic!]
			s		  [series!]
			required? [logic!]
			args	  [node!]
			p		  [int-ptr!]
			ref-array [int-ptr!]
			size	  [integer!]
			ret-set?  [logic!]
			call
	][
		routine?:  TYPE_OF(native) = TYPE_ROUTINE
		function?: any [routine? TYPE_OF(native) = TYPE_FUNCTION]
		fname:	   as red-word! pc - 1
		args:	   null

		either function? [
			fun: as red-function! native
			s: as series! fun/more/value
			blk: as red-block! s/offset + 1
			if TYPE_OF(blk) = TYPE_BLOCK [args: blk/node]
		][
			args: native/args
		]
		if null? args [
			args: preprocess-spec native
			
			either function? [
				blk/header: TYPE_BLOCK
				blk/head:	0
				blk/node:	args
			][
				native/args: args
			]
		]
		
		unless null? path [
			path-end: block/rs-tail as red-block! path
			if pos + 1 < path-end [						;-- test if refinement are following the function
				either null? path/args [				
					args: preprocess-options native path pos args fname function?
					path/args: args
				][
					args: path/args
				]
			]
		]
		
		s: as series! args/value
		value: s/offset
		tail:  s/tail
		required?: yes
		
		while [value < tail][
			expected: value + 1
			
			if TYPE_OF(value) <> TYPE_SET_WORD [
				switch TYPE_OF(expected) [
					TYPE_TYPESET [
						either required? [FETCH_ARGUMENT][none/push]
					]
					TYPE_LOGIC [
						stack/push expected
						bool: as red-logic! expected
						required?: bool/value
					]
					TYPE_VECTOR [
						vec: as red-vector! expected
						s: GET_BUFFER(vec)
						p: as int-ptr! s/offset
						size: (as-integer (as int-ptr! s/tail) - p) / 4
						ref-array: system/stack/top - size
						system/stack/top: ref-array			;-- reserve space on native stack for refs array
						copy-memory as byte-ptr! ref-array as byte-ptr! p size * 4
					]
					default [assert false]				;-- trap it, if stack corrupted 
				]
			]
			value: value + 2
		]
		
		unless function? [
			system/stack/top: ref-array					;-- reset native stack to our custom arguments frame
			call: as function! [] native/code			;-- direct call for actions/natives
			call
		]
		pc
	]
	
	eval-path: func [
		value   [red-value!]
		pc		[red-value!]							;-- path to evaluate
		end		[red-value!]
		set?	[logic!]
		get?	[logic!]
		sub?	[logic!]
		return: [red-value!]
		/local 
			path	[red-path!]
			head	[red-value!]
			tail	[red-value!]
			item	[red-value!]
			parent	[red-value!]
			gparent	[red-value!]
			saved	[red-value!]
			arg		[red-value!]
	][
		#if debug? = yes [if verbose > 0 [print-line "eval: path"]]
		
		path:   as red-path! value
		head:   block/rs-head as red-block! path
		tail:   block/rs-tail as red-block! path
		item:   head + 1
		saved:  stack/top
		
		if TYPE_OF(head) <> TYPE_WORD [
			print-line "*** Error: path value must start with a word!"
			halt
		]
		
		parent: _context/get as red-word! head
		unless get? [
			switch TYPE_OF(parent) [
				TYPE_ACTION								;@@ replace with TYPE_ANY_FUNCTION
				TYPE_NATIVE
				TYPE_ROUTINE
				TYPE_FUNCTION [
					pc: eval-code parent pc end yes path item - 1 parent
					return pc
				]
				TYPE_UNSET [
					fire [
						TO_ERROR(script no-value)
						head
					]
				]
				default [0]
			]
		]
				
		while [item < tail][
			#if debug? = yes [if verbose > 0 [print-line ["eval: path parent: " TYPE_OF(parent)]]]
			
			value: either any [
				TYPE_OF(item) = TYPE_GET_WORD 
				all [
					parent = head
					TYPE_OF(item) = TYPE_WORD
					TYPE_OF(parent) <> TYPE_OBJECT
				]
			][
				_context/get as red-word! item
			][
				item
			]
			switch TYPE_OF(value) [
				TYPE_UNSET [
					fire [
						TO_ERROR(script no-value)
						item
					]
				]
				TYPE_PAREN [
					stack/mark-native words/_body		;@@ ~paren
					eval as red-block! value yes		;-- eval paren content
					stack/unwind
					value: stack/top - 1
				]
				default [0]								;-- compilation pass-thru
			]
			#if debug? = yes [if verbose > 0 [print-line ["eval: path item: " TYPE_OF(value)]]]
			
			gparent: parent								;-- save grand-parent reference
			arg: either all [set? item + 1 = tail][stack/arguments][null]
			parent: actions/eval-path parent value arg
			
			unless get? [
				switch TYPE_OF(parent) [
					TYPE_ACTION								;@@ replace with TYPE_ANY_FUNCTION
					TYPE_NATIVE
					TYPE_ROUTINE
					TYPE_FUNCTION [
						pc: eval-code parent pc end yes path item gparent
						return pc
					]
					default [0]
				]
			]
			item: item + 1
		]
		
		stack/top: saved
		either sub? [stack/push parent][stack/set-last parent]
		pc
	]
	
	eval-code: func [
		value	[red-value!]
		pc		[red-value!]
		end		[red-value!]
		sub?	[logic!]
		path	[red-path!]
		slot 	[red-value!]
		parent	[red-value!]
		return: [red-value!]
		/local
			name [red-word!]
			obj  [red-object!]
			fun	 [red-function!]
			int	 [red-integer!]
			s	 [series!]
			ctx	 [node!]
	][
		name: as red-word! pc - 1
		if TYPE_OF(name) <> TYPE_WORD [name: words/_anon]
		
		switch TYPE_OF(value) [
			TYPE_ACTION 
			TYPE_NATIVE [
				#if debug? = yes [if verbose > 0 [log "pushing action/native frame"]]
				stack/mark-native name
				pc: eval-arguments as red-native! value pc end path slot 	;-- fetch args and exec
				either sub? [stack/unwind][stack/unwind-last]
				#if debug? = yes [
					if verbose > 0 [
						value: stack/arguments
						print-line ["eval: action/native return type: " TYPE_OF(value)]
					]
				]
			]
			TYPE_ROUTINE [
				#if debug? = yes [if verbose > 0 [log "pushing routine frame"]]
				stack/mark-native name
				pc: eval-arguments as red-native! value pc end path slot
				exec-routine as red-routine! value
				either sub? [stack/unwind][stack/unwind-last]
				#if debug? = yes [
					if verbose > 0 [
						value: stack/arguments
						print-line ["eval: routine return type: " TYPE_OF(value)]
					]
				]
			]
			TYPE_FUNCTION [
				#if debug? = yes [if verbose > 0 [log "pushing function frame"]]
				obj: as red-object! parent
				ctx: either all [
					parent <> null
					TYPE_OF(parent) = TYPE_OBJECT
				][
					obj/ctx
				][
					fun: as red-function! value
					s: as series! fun/more/value
					int: as red-integer! s/offset + 4
					either TYPE_OF(int) = TYPE_INTEGER [
						ctx: as node! int/value
					][
						name/ctx						;-- get a context from calling name
					]
				]
				stack/mark-func name
				pc: eval-arguments as red-native! value pc end path slot
				_function/call as red-function! value ctx
				either sub? [stack/unwind][stack/unwind-last]
				#if debug? = yes [
					if verbose > 0 [
						value: stack/arguments
						print-line ["eval: function return type: " TYPE_OF(value)]
					]
				]
			]
		]
		pc
	]
	
	eval-expression: func [
		pc		  [red-value!]
		end	  	  [red-value!]
		prefix?	  [logic!]								;-- TRUE => don't check for infix
		sub?	  [logic!]
		return:   [red-value!]
		/local
			next   [red-word!]
			value  [red-value!]
			left   [red-value!]
			w	   [red-word!]
			op	   [red-value!]
			sym	   [integer!]
			infix? [logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line ["eval: fetching value of type " TYPE_OF(pc)]]]
		
		infix?: no
		unless prefix? [
			next: as red-word! pc + 1
			CHECK_INFIX
			if infix? [
				stack/mark-native as red-word! pc + 1
				sub?: yes								;-- force sub? for infix expressions
				op: value
			]
		]
		
		switch TYPE_OF(pc) [
			TYPE_PAREN [
				stack/mark-native as red-word! pc		;@@ ~paren
				eval as red-block! pc yes
				either sub? [stack/unwind][stack/unwind-last]
				pc: pc + 1
			]
			TYPE_SET_WORD [
				stack/mark-native as red-word! pc		;@@ ~set
				word/push as red-word! pc
				pc: pc + 1
				pc: eval-expression pc end no yes
				word/set
				either sub? [stack/unwind][stack/unwind-last]
				#if debug? = yes [
					if verbose > 0 [
						value: stack/arguments
						print-line ["eval: set-word return type: " TYPE_OF(value)]
					]
				]
			]
			TYPE_SET_PATH [
				value: pc
				pc: pc + 1
				pc: eval-expression pc end no yes		;-- yes: push value on top of stack
				pc: eval-path value pc end yes no sub?
			]
			TYPE_GET_WORD [
				copy-cell _context/get as red-word! pc stack/push*
				pc: pc + 1
			]
			TYPE_LIT_WORD [
				either sub? [
					w: word/push as red-word! pc		;-- nested expression: push value
				][
					w: as red-word! stack/set-last pc	;-- root expression: return value
				]
				w/header: TYPE_WORD						;-- coerce it to a word!
				pc: pc + 1
			]
			TYPE_WORD [
				#if debug? = yes [
					if verbose > 0 [
						print "eval: '"
						print-symbol as red-word! pc
						print lf
					]
				]
				value: _context/get as red-word! pc
				
				if positive? in-func? [
					w: as red-word! pc
					sym: w/symbol
					case [
						sym = words/exit* [
							copy-cell unset-value stack/arguments
							stack/unroll stack/FLAG_FUNCTION
							throw THROWN_EXIT
						]
						sym = words/return* [
							pc: pc + 1
							either pc >= end [
								copy-cell unset-value stack/arguments
							][
								pc: eval-expression pc end no yes
							]
							stack/unroll stack/FLAG_FUNCTION
							throw THROWN_RETURN
						]
						true [0]
					]
				]
				pc: pc + 1
				
				switch TYPE_OF(value) [
					TYPE_UNSET [
						fire [
							TO_ERROR(script no-value)
							pc - 1
						]
					]
					TYPE_LIT_WORD [
						word/push as red-word! value	;-- push lit-word! on stack
					]
					TYPE_ACTION							;@@ replace with TYPE_ANY_FUNCTION
					TYPE_NATIVE
					TYPE_ROUTINE
					TYPE_FUNCTION [
						pc: eval-code value pc end sub? null null value
					]
					default [
						#if debug? = yes [if verbose > 0 [log "getting word value"]]
						either sub? [
							stack/push value			;-- nested expression: push value
						][
							stack/set-last value		;-- root expression: return value
						]
						#if debug? = yes [
							if verbose > 0 [
								value: stack/arguments
								print-line ["eval: word return type: " TYPE_OF(value)]
							]
						]
					]
				]
			]
			TYPE_PATH [
				value: pc
				pc: pc + 1
				pc: eval-path value pc end no no sub?
			]
			TYPE_GET_PATH [
				value: pc
				pc: pc + 1
				pc: eval-path value pc end no yes sub?
			]
			TYPE_LIT_PATH [
				value: stack/push pc
				value/header: TYPE_PATH
				pc: pc + 1
			]
			TYPE_OP [
				--NOT_IMPLEMENTED--						;-- op used in prefix mode
			]
			TYPE_ACTION							;@@ replace with TYPE_ANY_FUNCTION
			TYPE_NATIVE
			TYPE_ROUTINE
			TYPE_FUNCTION [
				value: pc + 1
				if value >= end [value: end]
				pc: eval-code pc value end sub? null null null
			]
			default [
				either sub? [
					stack/push pc						;-- nested expression: push value
				][
					stack/set-last pc					;-- root expression: return value
				]
				pc: pc + 1
			]
		]
		
		if infix? [
			pc: eval-infix op pc end sub?
			unless prefix? [
				either sub? [stack/unwind][stack/unwind-last]
			]
		]
		pc
	]

	eval-next: func [
		value	[red-value!]
		tail	[red-value!]
		sub?	[logic!]
		return: [red-value!]							;-- return start of next expression
	][
		stack/mark-native words/_body					;-- outer stack frame
		value: eval-expression value tail no sub?
		either sub? [stack/unwind][stack/unwind-last]
		value
	]
	
	eval: func [
		code   [red-block!]
		chain? [logic!]									;-- chain it with previous stack frame
		/local
			value [red-value!]
			tail  [red-value!]
			arg	  [red-value!]
	][
		value: block/rs-head code
		tail:  block/rs-tail code
		if value = tail [
			arg: stack/arguments
			arg/header: TYPE_UNSET
			exit
		]

		stack/mark-eval words/_body					;-- outer stack frame
		
		while [value < tail][
			#if debug? = yes [if verbose > 0 [log "root loop..."]]
			value: eval-expression value tail no no
			if value + 1 < tail [stack/reset]
		]
		either chain? [stack/unwind-last][stack/unwind]
	]
	
]