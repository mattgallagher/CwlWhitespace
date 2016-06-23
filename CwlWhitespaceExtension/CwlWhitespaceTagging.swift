//
//  CwlWhitespaceTagging.swift
//  CwlWhitespace
//
//  Created by Matthew Gallagher on 23/6/16.
//  Copyright © 2016 Matt Gallagher. All rights reserved.
//
//  Permission to use, copy, modify, and/or distribute this software for any
//  purpose with or without fee is hereby granted, provided that the above
//  copyright notice and this permission notice appear in all copies.
//
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
//  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
//  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
//  SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
//  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR
//  IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//

import Foundation

// These scopes are the stack elements of the pushdown automata
enum Scope {
	case lineComment
	case multilineComment
	case literal
	case interpolation
	case paren
	case block
	case switchScope
	case ternary
	case shadowedParen
	case shadowedBlock
}

// These tokens are the arrows between nodes of the pushdown automata
enum Token {
	// Single scalar tokens
	case tab
	case space
	case whitespace
	case quote
	case openBrace
	case closeBrace
	case openParen
	case closeParen
	case slash
	case backslash
	case asterisk
	case colon
	case comma
	case questionMark

	// Keywords
	case caseKeyword
	case defaultKeyword
	case switchKeyword
	case hashKeyword
	
	// Anything else is simply marked "other"
	case other
	
	// The following tokens may be multiple scalars, others will be a single scalar (for the purposes of this property, all keywords are "other" tokens)
	var aggregates: Bool {
		switch self {
		case .tab: fallthrough
		case .space: fallthrough
		case .whitespace: fallthrough
		case .other: return true
		default: return false
		}
	}
}

// These states are the nodes of the pushdown automata
enum ParseState {
	case indent
	case body
	case literal
	case lineComment
	case multilineComment
}

// An indent is required to be a "\t" scalar or a multiple of " " scalars, depending on this setting
public enum IndentationStyle {
	case tabs
	case spaces(Int)
}

// Violations of formatting rules within the current line are "tagged" to identify the type of violation
public struct TaggedRegion: Equatable {
	let start: Int
	let end: Int
	let tag: Tag
	let expected: Int
	init(start: Int, end: Int, tag: Tag, expected: Int) {
		self.start = start
		self.end = end
		self.tag = tag
		self.expected = expected
	}
}
public func ==(left: TaggedRegion, right: TaggedRegion) -> Bool {
	return (left.start == right.start && left.end == right.end && left.tag == right.tag && left.expected == right.expected)
}

// Tags are the types of formatting violations that can occur
public enum Tag {
	case incorrectIndent
	case multipleSpaces
	case unexpectedWhitespace
	case missingSpace
}

/// The WhitespaceTagger scans and parses single line at a time using a pushdown automata.
/// The purpose is to "tag" whitespace regions in the line that violate basic formatting rules.
public struct WhitespaceTagger {
	var stack: [Scope]
	let indentationStyle: IndentationStyle
	
	/// The constructor starts with an empty stack
	/// - parameter indentationStyle: defaults to `.tabs`
	public init(indentationStyle: IndentationStyle = .tabs) {
		self.stack = [Scope]()
		self.indentationStyle = indentationStyle
	}
	
	/// Runs the parser
	/// - parameter line: the text over which the parser will run
	/// - returns: an array of regions in the text that violated the whitespace expectations
	public mutating func parse(line: String) -> [TaggedRegion] {
		var scanner = ScalarScanner<String.UnicodeScalarView>(scalars: line.unicodeScalars)
		var regions = [TaggedRegion]()

		let tabs: Bool
		if case .tabs = indentationStyle {
			tabs = true
		} else {
			tabs = false
		}
		
		var state = stack.contains(.multilineComment) ? ParseState.multilineComment : ParseState.indent
		var column = 0
		var previous: (token: Token, length: Int)? = nil
		var current = nextToken(scanner: &scanner)
		var next = nextToken(scanner: &scanner)
		var consumeCount = 1
		
		var startOfLine = stack.count
		
		while let (token, length) = current {
			switch (state, token) {
			// In a multiline comment, only parse "*/" pairs, otherwise skip
			case (.multilineComment, .asterisk) where next?.token == .slash:
				_ = pop(scope: .multilineComment)
				state = stack.contains(.multilineComment) ? .multilineComment : .body
				consumeCount += 1
			case (.multilineComment, _): break
			
			// In a literal, parse end quotes and start interpolations
			case (.literal, .quote):
				_ = pop(scope: .literal)
				state = .body
			case (.literal, .backslash) where next?.token == .quote:
				consumeCount += 1
			case (.literal, .backslash) where next?.token == .openParen:
				push(scope: .interpolation)
				state = .body
				consumeCount += 1
			case (.literal, _): break
			
			// In a line comment, skip everything
			case (.lineComment, _): break

			// In the indent, parse tabs or spaces, according to indent rules, and everything else transitions to body
			case (.indent, .tab) where tabs == true: _ = validateIndent(regions: &regions, length: length, next: next)
			case (.indent, .tab):
				if validateIndent(regions: &regions, length: length, next: next) {
					flag(regions: &regions, tag: .incorrectIndent, column: column, length: length, expected: length)
				}
			case (.indent, .space) where tabs == false: _ = validateIndent(regions: &regions, length: length, next: next)
			case (.indent, .space):
				if validateIndent(regions: &regions, length: length, next: next) {
					flag(regions: &regions, tag: .incorrectIndent, column: column, length: length, expected: length)
				}
			case (.indent, _):
				if column == 0 {
					_ = validateIndent(regions: &regions, length: 0, next: current)
				}
				state = .body
				
				// Use a "continue" to force a reparse of the current token with changed state
				continue

			// In the body, spaces must be single, must not be preceeded by tab or other whitespace and must not preceed a colon.
			case (.body, .space) where length > 1: flag(regions: &regions, tag: .multipleSpaces, column: column, length: length, expected: 1)
			case (.body, .space) where previous?.token == .tab || previous?.token == .whitespace || next == nil: flag(regions: &regions, tag: .unexpectedWhitespace, column: column, length: length, expected: 0)
			case (.body, .space): break

			// Tabs and other whitespace are not permitted at all but based on whether they are preceeded by a space, tab or other whitepace should be replaced by either 1 space or deleted without replacement
			case (.body, .tab) where previous?.token == .space || previous?.token == .whitespace || next == nil: flag(regions: &regions, tag: .unexpectedWhitespace, column: column, length: length, expected: 0)
			case (.body, .tab): flag(regions: &regions, tag: .unexpectedWhitespace, column: column, length: length, expected: 1)
			case (.body, .whitespace) where previous?.token == .space || previous?.token == .tab || next == nil: flag(regions: &regions, tag: .unexpectedWhitespace, column: column, length: length, expected: 0)
			case (.body, .whitespace): flag(regions: &regions, tag: .unexpectedWhitespace, column: column, length: length, expected: 1)
			
			// Literal, brace and paren scopes
			case (.body, .quote):
				push(scope: .literal)
				state = .literal
			case (.body, .openBrace):
				push(scope: .block)
				if next != nil && next?.token != .space {
					flag(regions: &regions, tag: .missingSpace, column: column + 1, length: 0, expected: 1)
				}
				if previous != nil && previous?.token != .space && previous?.token != .openParen {
					flag(regions: &regions, tag: .missingSpace, column: column, length: 0, expected: 1)
				}
			case (.body, .closeBrace):
				if !pop(scope: .block) {
					_ = pop(scope: .shadowedBlock)
				}
				_ = pop(scope: .switchScope)
				if previous != nil && previous?.token != .space && previous?.token != .tab {
					flag(regions: &regions, tag: .missingSpace, column: column, length: 0, expected: 1)
				}
				if next != nil && next?.token != .space && next?.token != .closeParen && next?.token != .openParen && next?.token != .comma {
					flag(regions: &regions, tag: .missingSpace, column: column + 1, length: 0, expected: 1)
				}
			case (.body, .openParen): push(scope: .paren)
			case (.body, .closeParen):
				if pop(scope: .interpolation) {
					state = .literal
				} else {
					if !pop(scope: .paren) {
						_ = pop(scope: .shadowedParen)
					}
				}
			
			// Comments
			case (.body, .slash) where next?.token == .slash:
				state = .lineComment
				consumeCount += 1
			case (.body, .slash) where next?.token == .asterisk:
				push(scope: .multilineComment)
				state = .multilineComment
				consumeCount += 1
			case (.body, .slash) where next?.token == .openParen:
				push(scope: .interpolation)
				state = .body
				consumeCount += 1

			// Push and pop ternary from the stack
			case (.body, .questionMark) where previous?.token == .space && next?.token == .space: push(scope: .ternary)
			case (.body, .colon) where stack.last == .ternary:
				if previous?.token != .space {
					flag(regions: &regions, tag: .missingSpace, column: column, length: 0, expected: 1)
				}
				if next?.token != .space {
					flag(regions: &regions, tag: .missingSpace, column: column + 1, length: 0, expected: 1)
				}
				_ = pop(scope: .ternary)

			// Identical spacing rules for colons and commas
			case (.body, .colon): fallthrough
			case (.body, .comma):
				if next != nil && next?.token != .space {
					flag(regions: &regions, tag: .missingSpace, column: column + 1, length: 0, expected: 1)
				}
				if previous?.token == .space {
					flag(regions: &regions, tag: .unexpectedWhitespace, column: column - 1, length: 1, expected: 0)
				}

			// Push switch onto the stack (effectively a label for any proceeding block scope)
			case (.body, .switchKeyword): push(scope: .switchScope)
			
			// Other tokens are simply passed through
			case (.body, .slash): break
			case (.body, .asterisk): break
			case (.body, .backslash): break
			case (.body, .defaultKeyword): break
			case (.body, .caseKeyword): break
			case (.body, .hashKeyword): break
			case (.body, .questionMark): break
			case (.body, .other): break
			}
			
			// Tokens are consumed either 1 or 2 at a time (two token clusters include "//", "/*", "*/" and "\(")
			for _ in 0..<consumeCount {
				column += length
				previous = current
				current = next
				next = nextToken(scanner: &scanner)
			}
			consumeCount = 1
			
			// Track the "low water mark" of the stack
			if stack.count < startOfLine {
				startOfLine = stack.count
			}
		}
		
		// There's some cleanup of the stack to do at the end of the line:
		//	* every open block/paren on the line before the last should be marked "shadowed"
		// * if there's an open literal, the rest of the line should be scrubbed
		// * the .startOfLine marker needs to be removed
		var found = false
		for index in (startOfLine..<stack.endIndex).reversed() {
			switch stack[index] {
			case .literal: stack.removeSubrange(index..<stack.endIndex)
			case .block where !found: fallthrough
			case .paren where !found: found = true
			case .block: stack[index] = .shadowedBlock
			case .paren: stack[index] = .shadowedParen
			default: break
			}
		}
		
		return regions
	}
	
	// Counts the number of `scope` values in the `stack` array
	func count(scope: Scope) -> Int {
		return stack.reduce(0) { $0 + ($1 == scope ? 1 : 0) }
	}
	
	// Appends `scope` to the `stack` array.
	mutating func push(scope: Scope) {
		stack.append(scope)
	}
	
	// Identation within "switch" blocks follows a slightly different set of rules so we need to know if the immediately enclosing block is a switch block, which is determined by a `.switchScope` immediately preceeding the `.block`.
	func isMostRecentBlockPreceededBySwitch() -> Bool {
		var found = false
		for scope in stack.reversed() {
			if scope == .block {
				found = true
			} else if found {
				return scope == .switchScope
			}
		}
		return false
	}

	// Pop the specified scope only if it is the last item in the `stack` array.
	mutating func pop(scope: Scope) -> Bool {
		if stack.last == scope {
			stack.removeLast()
			return true
		}
		return false
	}

	// Check the indent width, flagging if incorrect.
	mutating func validateIndent(regions: inout [TaggedRegion], length: Int, next: (token: Token, length: Int)?) -> Bool {
		var offset = 0
		if let n = next {
			switch n.token {
			case .caseKeyword where isMostRecentBlockPreceededBySwitch(): fallthrough
			case .defaultKeyword where isMostRecentBlockPreceededBySwitch(): fallthrough
			case .hashKeyword: fallthrough
			case .closeBrace: fallthrough
			case .closeParen: offset = 1
			default: break
			}
		}
	
		var expectedIndentCount = count(scope: .paren) + count(scope: .block) - offset
		expectedIndentCount = expectedIndentCount < 0 ? 0 : expectedIndentCount
		
		switch indentationStyle {
		case .tabs where length == expectedIndentCount: return true
		case .tabs: flag(regions: &regions, tag: .incorrectIndent, column: 0, length: length, expected: expectedIndentCount)
		case .spaces(let perIndent) where length % perIndent == 0 && length / perIndent == expectedIndentCount: return true
		case .spaces(let perIndent): flag(regions: &regions, tag: .incorrectIndent, column: 0, length: length, expected: expectedIndentCount * perIndent)
		}
		
		return false
	}

	// Append a flagged region for emitting.
	mutating func flag(regions: inout [TaggedRegion], tag: Tag, column: Int, length: Int, expected: Int) {
		regions.append(TaggedRegion(start: column, end: column + length, tag: tag, expected: expected))
	}

	// Generates tokens for the parser by aggregating or substituting tokens from `readNext`.
	mutating func nextToken(scanner: inout ScalarScanner<String.UnicodeScalarView>) -> (token: Token, length: Int)? {
		var (token, scalar): (token: Token, scalar: UnicodeScalar)
		do {
			(token, scalar) = try readNext(scanner: &scanner)
		} catch { return nil }
		
		var count = 1
		if token.aggregates {
			// While aggregating "other" tokens, see if it matches one of the keywords we're interested in.
			typealias MatchBuffer = (UnicodeScalar, UnicodeScalar, UnicodeScalar, UnicodeScalar, UnicodeScalar, UnicodeScalar, UnicodeScalar)
			var possibleKeyword: (Token, MatchBuffer)?
			if token == .other {
				switch scalar {
				case "c": possibleKeyword = (Token.caseKeyword, ("a","s","e","\0","\0","\0","\0"))
				case "d": possibleKeyword = (Token.defaultKeyword, ("e","f","a","u","l","t","\0"))
				case "s": possibleKeyword = (Token.switchKeyword, ("w","i","t","c","h","\0","\0"))
				default: break
				}
			}

			do { repeat {
				let (nextToken, nextScalar) = try readNext(scanner: &scanner)
				if nextToken != token {
					try scanner.backtrack()
					break
				}
				
				// If this is a possible keyword match, make sure the scalars still match the expected
				if var (_, buffer) = possibleKeyword {
					if count < (sizeof(MatchBuffer.self) / sizeof(UnicodeScalar.self)) {
						withUnsafeMutablePointer(&buffer) {
							if UnsafeMutablePointer<UnicodeScalar>($0)[count - 1] != nextScalar {
								possibleKeyword = nil
							}
						}
					} else {
						possibleKeyword = nil
					}
				}

				count += 1
			} while true } catch {}
			
			// If we matched a keyword, substitute the token
			if let (tok, buffer) = possibleKeyword {
				let max = sizeof(MatchBuffer.self) / sizeof(UnicodeScalar.self)
				var b = buffer
				if count <= max && withUnsafePointer(&b, { UnsafePointer<UnicodeScalar>($0)[count - 1] == "\0" }) {
					token = tok
				}
			} else if scalar == "#" {
				token = .hashKeyword
			}
		}

		return (token, length: count)
	}

	// Peek at the next scalar and classify the token to which it would belong. NOTE: this is only intended for calling from `nextToken` which aggregates scalars and further matches keywords from "other" globs.
	mutating func readNext(scanner: inout ScalarScanner<String.UnicodeScalarView>) throws -> (token: Token, scalar: UnicodeScalar) {
		let scalar = try scanner.readScalar()
		switch scalar {
		// Xcode ensures that newlines only appear at the end of line strings. Since we don't care if a line ends with a newline or the end of file we can simply drop all newlines.
		case "\n": fallthrough

		// I'd love to reject Windows and classic Mac line endings entirely but it's not reasonable to reject the Xcode line endings setting. Just treat them like newlines.
		case "\r": throw ScalarScannerError.endedPrematurely(count: 1, at: scanner.consumed - 1)
		
		case " ": return (.space, scalar)
		case "\t": return (.tab, scalar)
		case "\"": return (.quote, scalar)
		case "{": return (.openBrace, scalar)
		case "}": return (.closeBrace, scalar)
		case "(": return (.openParen, scalar)
		case ")": return (.closeParen, scalar)
		case "/": return (.slash, scalar)
		case "\\": return (.backslash, scalar)
		case "*": return (.asterisk, scalar)
		case ":": return (.colon, scalar)
		case ",": return (.comma, scalar)
		case "?": return (.questionMark, scalar)

		// NOTE: I don't know if it's even possible for Xcode to pass a NUL through but it would mess with the keyword parsing so we can't have it classified as "other". Instead, classify it as unexpected whitespace and it will be flagged as invalid.
		case "\0": fallthrough
		
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
		case "\u{3000}": return (.whitespace, scalar)
		
		default: return (.other, scalar)
		}
	}
}
