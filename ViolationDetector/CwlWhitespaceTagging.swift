//
//  CwlWhitespaceTagging.swift
//  CwlWhitespace
//
//  Created by Matthew Gallagher on 19/6/16.
//  Copyright © 2016 Matt Gallagher. All rights reserved.
//

import Foundation

struct ParseContext: ParseContextProtocol {
	var stack: [TaggedRegion]
	var flagged = [TaggedRegion]()
	var line: Int
	var indent = "\t"
	
	init() {
		self.line = 0
		self.stack = [TaggedRegion(line: 0, start: 0, end: 0, tag: .indent)]
	}
	
	init(line: Int, stack: [TaggedRegion]) {
		self.line = line
		self.stack = stack
	}
}

enum Tag {
	// Body
	case block
	case interpolation
	case parenthetical
	
	// Other
	case blockComment
	case newline
	case indent
	case lineComment
	case stringLiteral
	case singleSpace
	case slash
	case whitespace
	case trailingWhitespace
}

struct TaggedRegion: Equatable {
	let line: Int
	let start: Int
	var end: Int
	var tag: Tag
	var expected: Int
	init(line: Int, start: Int, end: Int, tag: Tag, expected: Int = -1) {
		self.line = line
		self.start = start
		self.end = end
		self.tag = tag
		self.expected = expected
	}
}
func ==(left: TaggedRegion, right: TaggedRegion) -> Bool {
	return (left.line == right.line && left.start == right.start && left.end == right.end && left.tag == right.tag && left.expected == right.expected)
}

protocol ParseContextProtocol {
	var stack: [TaggedRegion] { get set }
	var flagged: [TaggedRegion] { get set }
	var line: Int { get set }
	var indent: String { get set }
}

private func isWhitespace(_ s: UnicodeScalar) -> Bool {
	switch s {
	case " ": fallthrough
	case "\r": fallthrough
	case "\t": fallthrough
	case "\u{000b}": fallthrough
	case "\u{000c}": fallthrough
	case "\u{0085}": fallthrough
	case "\u{00a0}": fallthrough
	case "\u{1680}": fallthrough
	case "\u{2000}"..."\u{200a}": fallthrough
	case "\u{2028}": fallthrough
	case "\u{2029}": fallthrough
	case "\u{202f}": fallthrough
	case "\u{205f}": fallthrough
	case "\u{3000}": return true
	default: return false
	}
}

internal extension ScalarScanner where T: ParseContextProtocol {
	mutating func parseLine() throws {
		do {
			repeat {
				switch context.stack.last?.tag ?? Tag.block {
				case .blockComment: try readBlockComment()
				case .indent: try readIndent()
				case .lineComment: try readLineComment()
				case .stringLiteral: try readStringLiteral()
				case .singleSpace: try readSingleSpace()
				case .slash: try readSlash()
				case .whitespace: try readWhitespace()
				default: try readBody()
				}
			} while index != scalars.endIndex
		} catch ScalarScannerError.endedPrematurely {}
		
		if context.stack.last?.tag == .newline {
			pop()
		}
		
		if let last = context.stack.last?.tag {
			switch last {
			case .singleSpace:
				context.stack[context.stack.endIndex - 1].tag = .whitespace
				fallthrough
			case .whitespace: flagAndPop()
			case .newline: throw unexpectedError()
			case .indent: pop()
			default: break
			}
		}
		
		pop(.lineComment)
		popLiterals()
		
		context.stack.append(TaggedRegion(line: context.line + 1, start: 0, end: 0, tag: .indent))
	}
	
	mutating func readBody() throws {
		switch try readScalar() {
		case "\n": push(.newline)
		case " ": push(.singleSpace)
		case "\r": fallthrough
		case "\t": fallthrough
		case "\u{000b}": fallthrough
		case "\u{000c}": fallthrough
		case "\u{0085}": fallthrough
		case "\u{00a0}": fallthrough
		case "\u{1680}": fallthrough
		case "\u{2000}"..."\u{200a}": fallthrough
		case "\u{2028}": fallthrough
		case "\u{2029}": fallthrough
		case "\u{202f}": fallthrough
		case "\u{205f}": fallthrough
		case "\u{3000}": push(.whitespace)
		case "/": push(.slash)
		case "(": push(.parenthetical)
		case ")": pop(.parenthetical)
		case "{": push(.block)
		case "}": pop(.block)
		case "\"": push(.stringLiteral)
		default: break
		}
	}
	
	mutating func readBlockComment() throws {
		try skipUntil(string: "*/")
		try skip(count: 2)
	}
	
	mutating func readIndent() throws {
		repeat {
			if conditional(scalar: "\n") {
				if indexAsInt == 1 {
					pop()
				} else {
					context.stack[context.stack.endIndex - 1].tag = .whitespace
					flagAndPop()
				}
				push(.newline)
			} else if conditional(string: context.indent) {
				print("Indent")
				continue
			} else if isWhitespace(try requirePeek()) {
				pop()
				try skip()
				push(.whitespace)
			} else {
				validateIndentAndPop()
			}
		} while context.stack.last?.tag == .indent
	}
	
	mutating func readLineComment() throws {
		skipWhile { _ in true }
		pop()
	}
	
	mutating func readStringLiteral() throws {
		try skipUntil(scalar: "\"")
		try skip()
		pop()
	}
	
	mutating func readSingleSpace() throws {
		pop()
		if isWhitespace(try requirePeek()) {
			push(.whitespace)
			try skip(count: 1)
		}
	}
	
	mutating func readSlash() throws {
		pop()
		switch try requirePeek() {
		case "*":
			try skip()
			push(.blockComment)
		case "/":
			try skip()
			push(.lineComment)
		default: break
		}
	}
	
	mutating func readWhitespace() throws {
		if let c = peek() {
			if isWhitespace(c) {
				try skip()
			} else {
				if let last = context.stack.last where last.start == 0 && c != "\n" {
					context.stack[context.stack.endIndex - 1].tag = .indent
					validateIndentAndPop()
				} else if c == "\n" {
					context.stack[context.stack.endIndex - 1].expected = 0
					flagAndPop()
				} else {
					context.stack[context.stack.endIndex - 1].expected = 1
					flagAndPop()
				}
			}
		} else {
			context.stack[context.stack.endIndex - 1].expected = 0
			flagAndPop()
		}
	}
	
	mutating func flagAndPop() {
		if var last = context.stack.last {
			last.end = indexAsInt
			context.flagged.append(last)
			context.stack.removeLast()
		}
	}
	
	mutating func validateIndentAndPop() {
		let expectedIndentCount = context.stack.reduce(0) { (count: Int, item: TaggedRegion) in
			switch item.tag {
			case .block: return count + 1
			case .parenthetical: return count + 1
			default: return count
			}
		}
		let indentWidth = context.indent.unicodeScalars.count
		if indexAsInt / indentWidth != expectedIndentCount {
			context.stack[context.stack.endIndex - 1].expected = expectedIndentCount
			flagAndPop()
		} else {
			pop()
		}
	}
	
	mutating func popLiterals() {
		pop(.stringLiteral)
	}
	
	mutating func push(_ tag: Tag) {
		let start = indexAsInt - 1
		context.stack.append(TaggedRegion(line: context.line, start: start, end: start, tag: tag))
	}
	
	mutating func pop() {
		context.stack.removeLast()
	}
	
	mutating func pop(_ tag: Tag) {
		for i in stride(from: context.stack.endIndex - 1, through: context.stack.startIndex, by: -1) {
			if context.stack[i].tag == tag {
				context.stack.remove(at: i)
				return
			}
		}
	}
}
