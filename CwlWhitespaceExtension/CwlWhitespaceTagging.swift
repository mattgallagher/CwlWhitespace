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
	case comment
	case string
	case interpolation
	case paren
	case block
	case bracket
	case hash
	case switchScope
	case pendingSwitch
	case ternary
	case shadowedParen
	case shadowedBracket
	case shadowedBlock
}

// These tokens are the arrows between nodes of the pushdown automata
enum Token {
	// Single scalar tokens
	case space
	case multiSpace
	case tab
	case whitespace
	case quote
	case openBrace
	case closeBrace
	case openBracket
	case closeBracket
	case openParen
	case closeParen
	case slash
	case backslash
	case asterisk
	case colon
	case comma
	case questionMark

	// Two scalar tokens
	case slashStar
	case starSlash
	case doubleSlash
	case slashQuote
	case slashOpenParen
	
	// Keywords
	case caseKeyword
	case defaultKeyword
	case switchKeyword
	case hashIfKeyword
	case hashElseifKeyword
	case hashEndifKeyword
	
	// Anything else is simply marked "other"
	case other
	
	// Consecutive instances of the following tokens will be grouped into a single token
	var aggregates: Bool {
		switch self {
		case .tab: fallthrough
		case .space: fallthrough
		case .whitespace: fallthrough
		case .other: return true
		default: return false
		}
	}

	// The following tokens may combine with the subsequent token to form a different token
	var possibleCompound: Bool {
		switch self {
		case .slash: fallthrough
		case .asterisk: fallthrough
		case .backslash: return true
		default: return false
		}
	}
}

// These states are the nodes of the pushdown automata
enum ParseState {
	case indent
	case indentEnded
	case body
	case spaceBody
	case needspaceBody
	case parenBody
	case literal
	case lineComment
	case multiComment
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
	var state: ParseState
	let indentationStyle: IndentationStyle
	
	/// The constructor starts with an empty stack
	/// - parameter indentationStyle: defaults to `.tabs`
	public init(indentationStyle: IndentationStyle = .tabs) {
		self.stack = [Scope]()
		self.indentationStyle = indentationStyle
		self.state = .indent
	}
	
	/// Runs the parser
	/// - parameter line: the text over which the parser will run
	/// - returns: an array of regions in the text that violated the whitespace expectations
	public mutating func parse(line: String) -> [TaggedRegion] {
		var scanner = ScalarScanner<String.UnicodeScalarView>(scalars: line.unicodeScalars)
		var regions = [TaggedRegion]()
		
		// If we're not starting inside a multiline comment, set state to "indent" at the start of a line
		if !stack.contains(.comment) {
			state = ParseState.indent
		}
		
		var buffer: MatchBuffer = ("\0", "\0", "\0", "\0", "\0", "\0", "\0", "\0")
		var column = 0
		var startOfLine = stack.count

		var current = nextToken(scanner: &scanner, buffer: &buffer)
		while let (token, length) = current {
			switch (state, token, stack) {
			// In a multiline comment, only parse "*/" pairs, otherwise skip
			case (.multiComment, .starSlash, UniqueScope(.comment)): arrow(to: .body, pop: .comment)
			case (.multiComment, .starSlash, _): arrow(to: .multiComment, pop: .comment)
			case (.multiComment, .slashStar, _): arrow(to: .multiComment, push: .comment)
			case (.multiComment, _, _): break
				
			// In a literal, parse end quotes and start interpolations
			case (.literal, .quote, _): arrow(to: .body, pop: .string)
			case (.literal, .slashOpenParen, _): arrow(to: .body, push: .interpolation)
			case (.literal, _, _): break
				
			// In a line comment, skip everything
			case (.lineComment, _, _): break
				
			// The indent must be a single tab or space token. Validation happens during indentEnded.
			case (.indent, .tab, _): arrow(to: .indentEnded)
			case (.indent, .space, _): arrow(to: .indentEnded)
			case (.indent, .multiSpace, _): arrow(to: .indentEnded)
			case (.indent, _, _):
				// No indent present, change to .indentEnded and reprocess this token
				arrow(to: .indentEnded)
				continue
			
			// The indent is validated after reading the *next* token since some tokens may use a reduced indent count.
			case (.indentEnded, .caseKeyword, TopScope(.switchScope)): fallthrough
			case (.indentEnded, .defaultKeyword, TopScope(.switchScope)): fallthrough
			case (.indentEnded, .hashEndifKeyword, _): fallthrough
			case (.indentEnded, .closeBrace, _): fallthrough
			case (.indentEnded, .closeParen, _):
				// Process the indent at a reduced level, change to .body and reprocess this token
				validateIndent(regions: &regions, length: column, offset: 1)
				arrow(to: .spaceBody)
				continue
			case (.indentEnded, _, _):
				// Process the indent normally, change to .body and reprocess this token
				validateIndent(regions: &regions, length: column, offset: 0)
				arrow(to: .spaceBody)
				continue

			// Handle post-whitespace conditions
			case (.spaceBody, .quote, _): arrow(to: .literal, push: .string)
			case (.spaceBody, .space, _):
				// This should be unreachable due to token aggregation. In any case, flag the problem and stay at .spaceBody
				flag(regions: &regions, tag: .unexpectedWhitespace, start: column, length: length, expected: 0)
				break
			case (.spaceBody, .openBrace, TopScope(.pendingSwitch)): arrow(to: .needspaceBody, pop: .pendingSwitch, push: .switchScope)
			case (.spaceBody, .openBrace, _): arrow(to: .needspaceBody, push: .block)
			case (.spaceBody, .colon, TopScope(.ternary)): arrow(to: .needspaceBody, pop: .ternary)
			case (.spaceBody, .colon, _): fallthrough
			case (.spaceBody, .comma, _):
				// This shouldn't follow a space. Flag the problem, change to .body and reprocess this token
				flag(regions: &regions, tag: .unexpectedWhitespace, start: column, length: length, expected: 0)
				arrow(to: .body)
				continue
			case (.spaceBody, .questionMark, _): arrow(to: .needspaceBody, push: .ternary)
			case (.spaceBody, .closeBrace, TopScope(.switchScope)): arrow(to: .needspaceBody, pop: .switchScope)
			case (.spaceBody, .closeBrace, TopScope(.block)): arrow(to: .needspaceBody, pop: .block)
			case (.spaceBody, .closeBrace, TopScope(.shadowedBlock)): arrow(to: .needspaceBody, pop: .shadowedBlock)
			case (.spaceBody, .closeBrace, _): break
			case (.spaceBody, _, _):
				// No special handling required, change to .body and reprocess normally
				arrow(to: .body)
				continue
			
			// The only purpose of .parenBody is to satisfy .openBrace which usually wants a preceeding space but is happy with a preceeding .openParen instead. In all other cases, it's just a .body.
			case (.parenBody, .quote, _): arrow(to: .literal, push: .string)
			case (.parenBody, .openBrace, _): arrow(to: .needspaceBody, push: .block)
			case (.parenBody, _, _):
				// No special handling required, change to .body and reprocess normally
				arrow(to: .body)
				continue

			// Handle state where a space is required
			case (.needspaceBody, .comma, _): break
			case (.needspaceBody, .closeParen, _): fallthrough
			case (.needspaceBody, .space, _):
				// We got the required space, now change to .body and reprocess this token
				arrow(to: .body)
				continue
			case (.needspaceBody, _, _):
				// Failed to get required space, flag the problem and change to .body to reprocess the token normally
				flag(regions: &regions, tag: .missingSpace, start: column, length: 0, expected: 1)
				arrow(to: .body)
				continue

			// In the body, spaces must be single, must not be preceeded by tab or other whitespace and must not preceed a colon.
			case (.body, .space, _): arrow(to: .spaceBody)
			case (.body, .tab, _):
				// Tabs should not appear in the body
				flag(regions: &regions, tag: .unexpectedWhitespace, start: column, length: length, expected: 1)
			case (.body, .multiSpace, _):
				// Multispace should not appear in the body
				flag(regions: &regions, tag: .multipleSpaces, start: column, length: length, expected: 1)
			case (.body, .whitespace, _):
				// Non-tab, non-space whitespace should not appear anywhere
				flag(regions: &regions, tag: .unexpectedWhitespace, start: column, length: length, expected: 1)
			case (.body, .quote, _): fallthrough
			case (.body, .openBrace, _): fallthrough
			case (.body, .closeBrace, _):
				// A close brace should follow a space. Flag the problem, change to .spaceBody and reprocess this token
				flag(regions: &regions, tag: .missingSpace, start: column, length: 0, expected: 1)
				arrow(to: .spaceBody)
				continue
			case (.body, .openBracket, _): arrow(to: .body, push: .bracket)
			case (.body, .closeBracket, TopScope(.bracket)): arrow(to: .body, pop: .bracket)
			case (.body, .closeBracket, TopScope(.shadowedBracket)): arrow(to: .body, pop: .shadowedBracket)
			case (.body, .closeBracket, _): break
			case (.body, .openParen, _): arrow(to: .parenBody, push: .paren)
			case (.body, .closeParen, TopScope(.interpolation)): arrow(to: .literal, pop: .interpolation)
			case (.body, .closeParen, TopScope(.paren)): arrow(to: .body, pop: .paren)
			case (.body, .closeParen, TopScope(.shadowedParen)): arrow(to: .body, pop: .shadowedParen)
			case (.body, .closeParen, _): break
			case (.body, .doubleSlash, _): arrow(to: .lineComment)
			case (.body, .slashStar, _): arrow(to: .multiComment, push: .comment)
			case (.body, .colon, TopScope(.ternary)):
				// A ternary operator colon should follow a space. Flag the problem, change to .spaceBody and reprocess this token
				flag(regions: &regions, tag: .missingSpace, start: column, length: 0, expected: 1)
				arrow(to: .spaceBody)
				continue
			case (.body, .colon, _): fallthrough
			case (.body, .comma, _): arrow(to: .needspaceBody)
			case (.body, .switchKeyword, _): arrow(to: .body, push: .pendingSwitch)
			case (.body, .hashIfKeyword, _): arrow(to: .body, push: .hash)
			case (.body, .hashEndifKeyword, TopScope(.hash)): arrow(to: .body, pop: .hash)
			case (.body, .hashEndifKeyword, _): break
			
			case (.body, .slash, _): break
			case (.body, .asterisk, _): break
			case (.body, .backslash, _): break
			case (.body, .defaultKeyword, _): break
			case (.body, .caseKeyword, _): break
			case (.body, .questionMark, _): break
			case (.body, .hashElseifKeyword, _): break
			case (.body, .slashOpenParen, _): break
			case (.body, .starSlash, _): break
			case (.body, .slashQuote, _): break
			case (.body, .other, _): break
			}
			
			// Track the "low water mark" of the stack
			if stack.count < startOfLine {
				startOfLine = stack.count
			}

			// Get the next token
			column += length
			if let next = nextToken(scanner: &scanner, buffer: &buffer) {
				current = next
			} else {
				break
			}
		}

		// Handle pending actions at end
		if let c = current {
			if state == .indentEnded {
				validateIndent(regions: &regions, length: column, offset: 0)
			} else if c.token == .space && state != .multiComment && state != .lineComment {
				flag(regions: &regions, tag: .unexpectedWhitespace, start: column - c.length, length: 1, expected: 0)
			}
		}
		
		// There's some cleanup of the stack to do at the end of the line:
		//	* every open block/paren on the line before the last should be marked "shadowed"
		// * if there's an open literal, the rest of the line should be scrubbed
		// * the .startOfLine marker needs to be removed
		var found = false
		for index in (startOfLine..<stack.endIndex).reversed() {
			switch stack[index] {
			case .string: stack.removeSubrange(index..<stack.endIndex)
			case .block where !found: fallthrough
			case .paren where !found: found = true
			case .block: stack[index] = .shadowedBlock
			case .paren: stack[index] = .shadowedParen
			default: break
			}
		}
		
		return regions
	}
	
	mutating func arrow(to newState: ParseState) {
		state = newState
	}
	
	mutating func arrow(to newState: ParseState, push scope: Scope) {
		stack.append(scope)
		state = newState
	}
	
	mutating func arrow(to newState: ParseState, pop scope: Scope) {
		if stack.last == scope {
			stack.removeLast()
		}
		state = newState
	}
	
	mutating func arrow(to newState: ParseState, pop scopeOld: Scope, push scopeNew: Scope) {
		if stack.last == scopeOld {
			stack.removeLast()
		}
		stack.append(scopeNew)
		state = newState
	}
	
	// Check the indent width, flagging if incorrect.
	@discardableResult
	mutating func validateIndent(regions: inout [TaggedRegion], length: Int, offset: Int) {
		var expectedIndentCount = stack.reduce(0) { count, scope -> Int in
			switch scope {
			case .paren: return count + 1
			case .block: return count + 1
			case .hash: return count + 1
			case .switchScope: return count + 1
			default: return count
			}
		}
		expectedIndentCount = expectedIndentCount < offset ? 0 : expectedIndentCount - offset
		
		switch indentationStyle {
		case .tabs where length == expectedIndentCount: break
		case .tabs: flag(regions: &regions, tag: .incorrectIndent, start: 0, length: length, expected: expectedIndentCount)
		case .spaces(let perIndent) where length % perIndent == 0 && length / perIndent == expectedIndentCount: break
		case .spaces(let perIndent): flag(regions: &regions, tag: .incorrectIndent, start: 0, length: length, expected: expectedIndentCount * perIndent)
		}
	}
	
	// Append a flagged region for emitting.
	mutating func flag(regions: inout [TaggedRegion], tag: Tag, start: Int, length: Int, expected: Int) {
		regions.append(TaggedRegion(start: start, end: start + length, tag: tag, expected: expected))
	}

	mutating func flag(regions: inout [TaggedRegion], tag: Tag, start: Int, length: Int, expected: Int, newState: ParseState) {
		flag(regions: &regions, tag: tag, start: start, length: length, expected: expected)
		state = newState
	}
	
	// Generates tokens for the parser by aggregating or substituting tokens from `readNext`.
	mutating func nextToken(scanner: inout ScalarScanner<String.UnicodeScalarView>, buffer: inout MatchBuffer) -> (token: Token, length: Int)? {
		var (token, scalar): (token: Token, scalar: UnicodeScalar)
		do {
			(token, scalar) = try readNext(scanner: &scanner)
		} catch { return nil }
		
		var count = 1
		if token.aggregates {
			// While aggregating "other" tokens, see if it matches one of the keywords we're interested in.
			var possibleKeyword: Bool = false
			if token == .other {
				switch scalar {
				case "c": fallthrough
				case "d": fallthrough
				case "s": fallthrough
				case "#":
					possibleKeyword = true
					buffer = (scalar, "\0", "\0", "\0", "\0", "\0", "\0", "\0")
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
				if possibleKeyword {
					if count < (sizeof(MatchBuffer.self) / sizeof(UnicodeScalar.self)) {
						withUnsafeMutablePointer(&buffer) {
							UnsafeMutablePointer<UnicodeScalar>($0)[count] = nextScalar
						}
					} else {
						possibleKeyword = false
					}
				}
				
				count += 1
			} while true } catch {}
			
			// If we matched a keyword, substitute the token
			if possibleKeyword {
				switch scalar {
				case "c":
					var suffix: MatchBuffer = ("c", "a", "s", "e", "\0", "\0", "\0", "\0")
					if match(first: &buffer, second: &suffix) { token = .caseKeyword }
				case "d":
					var suffix: MatchBuffer = ("d", "e", "f", "a", "u", "l", "t", "\0")
					if match(first: &buffer, second: &suffix) { token = .defaultKeyword }
				case "s":
					var suffix: MatchBuffer = ("s", "w", "i", "t", "c", "h", "\0", "\0")
					if match(first: &buffer, second: &suffix) { token = .switchKeyword }
				case "#":
					var suffix1: MatchBuffer = ("#", "i", "f", "\0", "\0", "\0", "\0", "\0")
					var suffix2: MatchBuffer = ("#", "e", "l", "s", "e", "i", "f", "\0")
					var suffix3: MatchBuffer = ("#", "e", "l", "s", "e", "\0", "\0", "\0")
					var suffix4: MatchBuffer = ("#", "e", "n", "d", "i", "f", "\0", "\0")
					if match(first: &buffer, second: &suffix1) { token = .hashIfKeyword }
					else if match(first: &buffer, second: &suffix2) { token = .hashElseifKeyword }
					else if match(first: &buffer, second: &suffix3) { token = .hashElseifKeyword }
					else if match(first: &buffer, second: &suffix4) { token = .hashEndifKeyword }
				default: break
				}
			} else if token == .space && count > 1 {
				token = .multiSpace
			}
		} else if token.possibleCompound {
			do {
				let (nextToken, _) = try readNext(scanner: &scanner)
				count += 1
				
				switch (token, nextToken) {
				case (.slash, .slash): token = .doubleSlash
				case (.slash, .asterisk): token = .slashStar
				case (.asterisk, .slash): token = .starSlash
				case (.backslash, .openParen): token = .slashOpenParen
				case (.backslash, .quote): token = .slashQuote
				default:
					try scanner.backtrack()
					count -= 1
				}
			} catch {}
		}
		
		return (token, length: count)
	}
	
	// Peek at the next scalar and classify the token to which it would belong. NOTE: this is only intended for calling from `nextToken` which aggregates scalars and further matches keywords from "other" globs.
	mutating func readNext(scanner: inout ScalarScanner<String.UnicodeScalarView>) throws -> (token: Token, scalar: UnicodeScalar) {
		let scalar = try scanner.readScalar()
		switch scalar {
		// Xcode ensures that newlines only appear at the end of line strings. Since we don't care if a line ends with a newline or the end of file we can simply drop all newlines (by returning an "end of collection" error).
		case "\n": fallthrough
			
		// I'd love to reject Windows and classic Mac line endings entirely but it's not reasonable to reject the Xcode line endings setting. Just treat them like newlines.
		case "\r": throw ScalarScannerError.endedPrematurely(count: 1, at: scanner.consumed - 1)
			
		case " ": return (.space, scalar)
		case "\t": return (.tab, scalar)
		case "\"": return (.quote, scalar)
		case "{": return (.openBrace, scalar)
		case "}": return (.closeBrace, scalar)
		case "[": return (.openBracket, scalar)
		case "]": return (.closeBracket, scalar)
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
			
		// Standard set of Unicode whitespace scalars
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

struct UniqueScope {
	let scope: Scope
	init(_ scope: Scope) {
		self.scope = scope
	}
}

func ~=(left: UniqueScope, right: Array<Scope>) -> Bool {
	return right.reduce(0) { $0 + ($1 == left.scope ? 1 : 0) } == 1
}

struct TopScope {
	let scope: Scope
	init(_ scope: Scope) {
		self.scope = scope
	}
}

func ~=(left: TopScope, right: Array<Scope>) -> Bool {
	return right.last == left.scope
}

typealias MatchBuffer = (UnicodeScalar, UnicodeScalar, UnicodeScalar, UnicodeScalar, UnicodeScalar, UnicodeScalar, UnicodeScalar, UnicodeScalar)
func match(first: inout MatchBuffer, second: inout MatchBuffer) -> Bool {
	return withUnsafePointers(&first, &second) { (firstPtr, secondPtr) -> Bool in
		memcmp(UnsafePointer<Void>(firstPtr), UnsafePointer<Void>(secondPtr), sizeof(MatchBuffer.self)) == 0
	}
}
