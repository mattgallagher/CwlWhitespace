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

// These tokens are the arrows between nodes of the pushdown automata
enum Tok {
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
	case openAngle
	case closeAngle
	case backslash
	case colon
	case comma
	case op
	case questionMark
	case identifier
	case hash
	case digit
	case dollar
	case combining
	case period
	case semiColon
	case at
	case backtick
	
	// Two scalar tokens
	case slashStar
	case starSlash
	case doubleSlash
	
	// Keywords
	case caseKeyword
	case defaultKeyword
	case switchKeyword
	case hashIfKeyword
	case hashElseKeyword
	case hashElseifKeyword
	case hashEndifKeyword
	
	// Newlines and carriage returns
	case endOfLine
	
	// Scalars that shouldn't be used at all – even in comments
	case invalid
}

// These scopes are the stack elements of the pushdown automata
enum Scope {
	case comment
	case string
	case interpolation
	case paren
	case angle
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

// These states are the nodes of the pushdown automata
enum ParseState {
	// Skipping (potentially nested) /* */ comments
	case multiComment
	
	// Inside a string literal
	case literal
	
	// Backslash inside a string literal just parsed
	case escape
	
	// Skipping to end of line
	case lineComment
	
	// Start of the line
	case indent
	case invalidIndent
	
	// First non-indent token is parsed in this state so any effect on the indent can be considered
	case indentEnded
	
	// Space after non-whitespace, non-operator.
	case spaceBody
	
	// An identifier just parsed (or other token that may be followed by a postfix operator, dot operator or space but not another identifier or open scope)
	case identifierBody
	
	// Left paren just parsed
	case parenBody
	
	// Left brace just parsed
	case braceBody
	
	// Left brace just parsed
	case angleBody
	
	// An operator parsed that should be followed a space or a dot operator (i.e. a left-hugging colon, postfix operator or comma)
	case postfix
	
	// A space, then an operator just parsed (i.e. binary operator or prefix operator)
	case prefix
	
	// A space, then an operator just parsed (i.e. binary operator or prefix operator)
	case infix
	
	// Non-whitespace expected (no other states will be flagged except those that are invalid everywhere). Used as the starting state for a line and the fallback state for other scenarios.
	case body
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
	case invalidCharacter
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
	
	public mutating func parseLine(_ line: String) -> [TaggedRegion] {
		return parseLine(line.unicodeScalars)
	}
	
	/// Runs the parser
	/// - parameter line: the text over which the parser will run
	/// - returns: an array of regions in the text that violated the whitespace expectations
	public mutating func parseLine<C: Collection>(_ line: C) -> [TaggedRegion] where C.Iterator.Element == UnicodeScalar, C.SubSequence: Collection, C.SubSequence.Iterator.Element == UnicodeScalar, C.SubSequence.IndexDistance == Int {
		var scanner = ScalarScanner<C>(scalars: line)
		var regions = [TaggedRegion]()
		
		// If we're not starting inside a multiline comment, set state to "indent" at the start of a line
		if !stack.contains(.comment) {
			state = ParseState.indent
		}
		
		var column = 0
		var previousLength = 0
		var startOfLine = stack.count
		var previousTok = Tok.invalid
		var token = nextToken(scanner: &scanner)
		
		repeat {
			#if DEBUG
				// Handy debug statement:
				print("Column: \(column), state: \(state), token: \(token.tok), length: \(token.slice.count), stack count: \(stack.count), stack top: \(stack.last.map { String($0) } ?? "none"), region count: \(regions.count), text: \(token.slice)")
			#endif
			
			switch (state, token.tok, stack) {
			// Skipping (potentially nested) /* */ comments
			case (.multiComment, .starSlash, UniqueScope(.comment)): arrow(to: .identifierBody, pop: .comment)
			case (.multiComment, .starSlash, _): arrow(to: .multiComment, pop: .comment)
			case (.multiComment, .slashStar, _): arrow(to: .multiComment, push: .comment)
			case (.multiComment, _, _): break
				
			// Inside a string literal
			case (.literal, .backslash, _): arrow(to: .escape)
			case (.literal, .quote, _): arrow(to: .identifierBody, pop: .string)
			case (.literal, _, _): break
				
			// Backslash inside a string literal just parsed
			case (.escape, .openParen, _): arrow(to: .parenBody, push: .interpolation)
			case (.escape, _, _): arrow(to: .literal)
				
			// Skipping to end of line
			case (.lineComment, _, _): break
				
			// Start of the line
			case (.indent, IndentToken(indentationStyle), _): break
			case (.indent, .space, _): arrow(to: .invalidIndent)
			case (.indent, .multiSpace, _): arrow(to: .invalidIndent)
			case (.indent, .tab, _): arrow(to: .invalidIndent)
			case (.indent, .whitespace, _): arrow(to: .invalidIndent)
			case (.indent, _, _):
				arrow(to: .indentEnded)
				continue
				
			// Incorrect whitespace encountered during indent
			case (.invalidIndent, .space, _): break
			case (.invalidIndent, .multiSpace, _): break
			case (.invalidIndent, .tab, _): break
			case (.invalidIndent, .whitespace, _): break
			case (.invalidIndent, _, _):
				flag(regions: &regions, tag: .incorrectIndent, start: 0, length: column, expected: expectedWidthForIndent(endingWith: token.tok))
				arrow(to: .body)
				continue
				
			// First non-indent token is parsed in this state so any effect on the indent can be considered
			case (.indentEnded, ValidIndent(self, column), _):
				arrow(to: .body)
				continue
			case (.indentEnded, _, _):
				flag(regions: &regions, tag: .incorrectIndent, start: 0, length: column, expected: expectedWidthForIndent(endingWith: token.tok))
				arrow(to: .body)
				continue
				
			// Space after non-whitespace, non-operator.
			case (.spaceBody, .colon, TopScope(.ternary)): arrow(to: .infix, pop: .ternary)
			case (.spaceBody, .questionMark, _): arrow(to: .infix, push: .ternary)
			case (.spaceBody, .op, _): arrow(to: .infix)
			case (.spaceBody, .openAngle, _): arrow(to: .infix)
			case (.spaceBody, .closeAngle, _): arrow(to: .infix)
			case (.spaceBody, .period, _): arrow(to: .infix)
			case (.spaceBody, .colon, _): fallthrough
			case (.spaceBody, .closeParen, _): fallthrough
			case (.spaceBody, .endOfLine, _): fallthrough
			case (.spaceBody, .comma, _):
				// This shouldn't follow a space. Flag the problem, change to .body and reprocess this token.
				// WARNING: this flags the *previous* read scalar. There's a chance this scalar is already flagged, resulting in overlapping regions. This must be carefully handled.
				flag(regions: &regions, tag: .unexpectedWhitespace, start: column - 1, length: token.slice.count, expected: 0)
				arrow(to: .body)
				continue
			case (.spaceBody, _, _):
				arrow(to: .body)
				continue
				
			// An identifier just parsed (or other token that may be followed by a postfix operator, dot operator or space but not another identifier or open scope)
			case (.identifierBody, .space, _): arrow(to: .spaceBody)
			case (.identifierBody, .openBrace, _): fallthrough
			case (.identifierBody, .closeBrace, _):
				flag(regions: &regions, tag: .missingSpace, start: column, length: 0, expected: 1)
				arrow(to: .body)
				continue
			case (.identifierBody, .tab, _): fallthrough
			case (.identifierBody, .whitespace, _):
				flag(regions: &regions, tag: .unexpectedWhitespace, start: column, length: token.slice.count, expected: 1)
				arrow(to: .spaceBody)
			case (.identifierBody, .multiSpace, _):
				flag(regions: &regions, tag: .multipleSpaces, start: column, length: token.slice.count, expected: 1)
				arrow(to: .spaceBody)
			case (.identifierBody, _, _):
				arrow(to: .body)
				continue
				
			// Left paren just parsed
			case (.parenBody, .closeBrace, _):
				flag(regions: &regions, tag: .missingSpace, start: column, length: 0, expected: 1)
				arrow(to: .body)
				continue
			case (.parenBody, .openBrace, _):
				// Space requirement satisfied without a space. Change to .spaceBody and reprocess normally.
				arrow(to: .braceBody)
				continue
			case (.parenBody, .op, _): arrow(to: .infix)
			case (.parenBody, .period, _): arrow(to: .infix)
			case (.parenBody, .endOfLine, _): arrow(to: .body)
			case (.parenBody, _, _):
				arrow(to: .body)
				continue
				
			// Left angle just parsed
			case (.angleBody, _, _):
				arrow(to: .body)
				continue
				
			// Left brace just parsed
			case (.braceBody, .openBrace, _): fallthrough
			case (.braceBody, .closeBrace, _):
				arrow(to: .body)
				continue
			case (.braceBody, .space, _): arrow(to: .spaceBody)
			case (.braceBody, .endOfLine, _): arrow(to: .body)
			case (.braceBody, _, _):
				flag(regions: &regions, tag: .missingSpace, start: column, length: 0, expected: 1)
				arrow(to: .body)
				continue
				
			// An operator parsed that should be followed a space or a dot operator (i.e. a left-hugging colon, postfix operator or comma)
			case (.postfix, .openParen, _) where previousTok == .period: fallthrough
			case (.postfix, .quote, _) where previousTok == .period: fallthrough
			case (.postfix, .digit, _) where previousTok == .period: fallthrough
			case (.postfix, .dollar, _) where previousTok == .period: fallthrough
			case (.postfix, .identifier, _) where previousTok == .period:
				arrow(to: .body)
				continue
			case (.postfix, .openAngle, _): break
			case (.postfix, .closeAngle, _): break
			case (.postfix, .openParen, _) where previousTok == .op: fallthrough
			case (.postfix, .quote, _) where previousTok == .op: fallthrough
			case (.postfix, .digit, _) where previousTok == .op: fallthrough
			case (.postfix, .dollar, _) where previousTok == .op: fallthrough
			case (.postfix, .identifier, _) where previousTok == .op:
				flag(regions: &regions, tag: .missingSpace, start: column - previousLength, length: 0, expected: 1)
				flag(regions: &regions, tag: .missingSpace, start: column, length: 0, expected: 1)
				arrow(to: .infix)
				continue
			case (.postfix, .openParen, _): fallthrough
			case (.postfix, .quote, _): fallthrough
			case (.postfix, .digit, _): fallthrough
			case (.postfix, .dollar, _): fallthrough
			case (.postfix, .identifier, _):
				flag(regions: &regions, tag: .missingSpace, start: column, length: 0, expected: 1)
				arrow(to: .body)
				continue
			case (.postfix, .space, _): arrow(to: .spaceBody)
			case (.postfix, .endOfLine, _): arrow(to: .body)
			case (.postfix, _, _):
				flag(regions: &regions, tag: .missingSpace, start: column, length: 0, expected: 1)
				arrow(to: .body)
				continue
				
			// A space, then an operator just parsed (i.e. binary operator or prefix operator)
			case (.prefix, .openBrace, _): fallthrough
			case (.prefix, .closeBrace, _):
				flag(regions: &regions, tag: .missingSpace, start: column, length: 0, expected: 1)
				arrow(to: .body)
				continue
			case (.prefix, _, _):
				arrow(to: .body)
				continue
				
			// A space, then an operator just parsed (i.e. binary operator or prefix operator)
			case (.infix, .space, _) where previousTok == .period:
				flag(regions: &regions, tag: .unexpectedWhitespace, start: column - previousLength - 1, length: 1, expected: 0)
				flag(regions: &regions, tag: .unexpectedWhitespace, start: column, length: token.slice.count, expected: 0)
				arrow(to: .spaceBody)
			case (.infix, .space, _):
				// We got the required space
				arrow(to: .spaceBody)
			case (.infix, _, _) where previousTok == .closeAngle:
				flag(regions: &regions, tag: .unexpectedWhitespace, start: column - previousLength - 1, length: 1, expected: 0)
				arrow(to: .body)
				continue
			case (.infix, .openParen, _): fallthrough
			case (.infix, .quote, _): fallthrough
			case (.infix, .digit, _): fallthrough
			case (.infix, .dollar, _): fallthrough
			case (.infix, .identifier, _): fallthrough
			case (.infix, .openBracket, _):
				arrow(to: .prefix)
				continue
			case (.infix, .openBrace, _): fallthrough
			case (.infix, .closeBrace, _):
				flag(regions: &regions, tag: .missingSpace, start: column, length: 0, expected: 1)
				arrow(to: .body)
				continue
			case (.infix, .comma, _): break
			case (.infix, .closeParen, _): fallthrough
			case (.infix, .closeBracket, _): fallthrough
			case (.infix, .endOfLine, _): fallthrough
			case (.infix, _, _):
				// Failed to get required space, flag the problem and change to .body to reprocess the token normally
				flag(regions: &regions, tag: .missingSpace, start: column, length: 0, expected: 1)
				arrow(to: .body)
				continue
				
			// Non-whitespace expected (no other states will be flagged except those that are invalid everywhere). Used as the starting state for a line and the fallback state for other scenarios.
			case (.body, .space, _): fallthrough
			case (.body, .tab, _): fallthrough
			case (.body, .whitespace, _): fallthrough
			case (.body, .multiSpace, _):
				flag(regions: &regions, tag: .unexpectedWhitespace, start: column, length: token.slice.count, expected: 0)
			case (.body, .quote, _): arrow(to: .literal, push: .string)
			case (.body, .openBrace, TopScope(.pendingSwitch)): arrow(to: .braceBody, pop: .pendingSwitch, push: .switchScope)
			case (.body, .openBrace, _): arrow(to: .braceBody, push: .block)
			case (.body, .closeBrace, TopScope(.switchScope)): arrow(to: .identifierBody, pop: .switchScope)
			case (.body, .closeBrace, TopScope(.block)): arrow(to: .identifierBody, pop: .block)
			case (.body, .closeBrace, TopScope(.shadowedBlock)): arrow(to: .identifierBody, pop: .shadowedBlock)
			case (.body, .closeBrace, _): break
			case (.body, .openBracket, _): arrow(to: .body, push: .bracket)
			case (.body, .closeBracket, TopScope(.bracket)): arrow(to: .identifierBody, pop: .bracket)
			case (.body, .closeBracket, TopScope(.shadowedBracket)): arrow(to: .identifierBody, pop: .shadowedBracket)
			case (.body, .closeBracket, _): break
			case (.body, .openParen, _): arrow(to: .parenBody, push: .paren)
			case (.body, .closeParen, TopScope(.interpolation)): arrow(to: .literal, pop: .interpolation)
			case (.body, .closeParen, TopScope(.paren)): arrow(to: .identifierBody, pop: .paren)
			case (.body, .closeParen, TopScope(.shadowedParen)): arrow(to: .identifierBody, pop: .shadowedParen)
			case (.body, .closeParen, _): break
			case (.body, .openAngle, _): arrow(to: .angleBody, push: .angle)
			case (.body, .closeAngle, TopScope(.angle)): arrow(to: .identifierBody, pop: .angle)
			case (.body, .closeAngle, _): break
			case (.body, .backslash, _): break
			case (.body, .colon, TopScope(.ternary)): arrow(to: .infix)
			case (.body, .colon, _): arrow(to: .postfix)
			case (.body, .comma, _): arrow(to: .postfix)
			case (.body, .op, _): arrow(to: .postfix)
			case (.body, .questionMark, _): arrow(to: .postfix)
			case (.body, .identifier, _): arrow(to: .identifierBody)
			case (.body, .hash, _): arrow(to: .prefix)
			case (.body, .digit, _): arrow(to: .identifierBody)
			case (.body, .dollar, _): arrow(to: .prefix)
			case (.body, .combining, _): break
			case (.body, .period, _): arrow(to: .postfix)
			case (.body, .semiColon, _): arrow(to: .postfix)
			case (.body, .at, _): arrow(to: .prefix)
			case (.body, .backtick, _): arrow(to: .postfix)
			case (.body, .slashStar, _): arrow(to: .multiComment, push: .comment)
			case (.body, .starSlash, _): break
			case (.body, .doubleSlash, _): arrow(to: .lineComment)
			case (.body, .caseKeyword, _): arrow(to: .identifierBody)
			case (.body, .defaultKeyword, _): arrow(to: .identifierBody)
			case (.body, .switchKeyword, _): arrow(to: .identifierBody, push: .pendingSwitch)
			case (.body, .hashIfKeyword, _): arrow(to: .identifierBody, push: .hash)
			case (.body, .hashElseKeyword, _): arrow(to: .identifierBody)
			case (.body, .hashElseifKeyword, _): arrow(to: .identifierBody)
			case (.body, .hashEndifKeyword, TopScope(.hash)): arrow(to: .identifierBody, pop: .hash)
			case (.body, .hashEndifKeyword, _): arrow(to: .identifierBody)
			case (.body, .endOfLine, _): break
			case (.body, .invalid, _):
				flag(regions: &regions, tag: .invalidCharacter, start: column, length: token.slice.count, expected: 0)
			}
			
			// Track the "low water mark" of the stack
			if stack.count < startOfLine {
				startOfLine = stack.count
			}
			
			// Consume the token
			previousLength = token.slice.count
			column += previousLength
			
			// Break out of the loop if at end
			if token.tok == .endOfLine {
				break
			}
			
			// Start the next token
			previousTok = token.tok
			token = nextToken(scanner: &scanner)
		} while true
		
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
	
	func indentWidth() -> Int {
		switch indentationStyle {
		case .tabs: return 1
		case .spaces(let perIndent): return perIndent
		}
	}
	
	func expectedIndentWidth() -> Int {
		return stack.reduce(0) { count, scope -> Int in
			switch scope {
			case .paren: return count + 1
			case .block: return count + 1
			case .hash: return count + 1
			case .switchScope: return count + 1
			default: return count
			}
		} * indentWidth()
	}
	
	func expectedWidthForIndent(endingWith token: Tok) -> Int {
		switch (token, stack.last) {
		case (.hashEndifKeyword, _): fallthrough
		case (.hashElseifKeyword, _): fallthrough
		case (.hashElseKeyword, _): fallthrough
		case (.closeBrace, _): fallthrough
		case (.closeBracket, _): fallthrough
		case (.closeParen, _): fallthrough
		case (.defaultKeyword, .some(.switchScope)): fallthrough
		case (.caseKeyword, .some(.switchScope)):
			return expectedIndentWidth() - indentWidth()
		case (.slashStar, .some(.switchScope)): fallthrough
		case (.doubleSlash, .some(.switchScope)): fallthrough
		default: return expectedIndentWidth()
		}
	}
	
	// Append a flagged region for emitting.
	mutating func flag(regions: inout [TaggedRegion], tag: Tag, start: Int, length: Int, expected: Int) {
		regions.append(TaggedRegion(start: start, end: start + length, tag: tag, expected: expected))
	}
}

struct Token<C: Collection> where C.Iterator.Element == UnicodeScalar, C.SubSequence: Collection, C.SubSequence.IndexDistance == Int {
	let tok: Tok
	let slice: C.SubSequence
}

enum LexerState: Error {
	case start
	case aggregating(Tok)
	case aggregatingIdentifier
	case possibleOp((UnicodeScalar) -> LexerState)
	case splitOp(Tok, Int)
	case periodOp
	case possibleKeyword((UnicodeScalar) -> LexerState)
	case keywordOrPossibleKeyword(Tok, (UnicodeScalar) -> LexerState)
	case keyword(Tok)
	case singleSpace
	case singleQuestionMark
	case singleOpenAngle
	case singleCloseAngle
	
	func finalize() -> Tok {
		switch self {
		case .start: return .endOfLine
		case .aggregating(let t): return t
		case .aggregatingIdentifier: return .identifier
		case .possibleOp: return .op
		case .singleSpace: return .space
		case .splitOp(let t, _): return t
		case .periodOp: return .period
		case .singleQuestionMark: return .questionMark
		case .singleOpenAngle: return .openAngle
		case .singleCloseAngle: return .closeAngle
		case .possibleKeyword: return .identifier
		case .keywordOrPossibleKeyword(let t, _): return t
		case .keyword(let t): return t
		}
	}
}

// Generates tokens for the parser by aggregating or substituting tokens from `readNext`.
func nextToken<C: Collection>(scanner: inout ScalarScanner<C>) -> Token<C> where C.Iterator.Element == UnicodeScalar, C.SubSequence: Collection, C.SubSequence.IndexDistance == Int {
	let start = scanner.index
	var state = LexerState.start
	
	do { repeat {
		let scalar = try scanner.readScalar()
		let tok = classify(scalar)
		
		switch (state, tok) {
		case (.start, .endOfLine): return Token<C>(tok: .endOfLine, slice: scanner.scalars[start..<scanner.index])
		case (.start, .hash): state = startHash(scalar)
		case (.start, .identifier): state = startKeyword(scalar)
		case (.start, .op): state = startOp(scalar)
		case (.start, .space): state = .singleSpace
		case (.start, .period): state = .periodOp
		case (.start, .questionMark): state = .singleQuestionMark
		case (.start, .openAngle): state = .singleOpenAngle
		case (.start, .closeAngle): state = .singleCloseAngle
		case (.start, .tab): fallthrough
		case (.start, .whitespace): fallthrough
		case (.start, .digit): fallthrough
		case (.start, .combining): fallthrough
		case (.start, .invalid): fallthrough
		case (.start, .tab): state = .aggregating(tok)
		case (.start, _): return Token<C>(tok: tok, slice: scanner.scalars[start..<scanner.index])
			
		case (.keyword, .identifier): state = .aggregatingIdentifier
		case (.keyword, .combining): state = .aggregatingIdentifier
		case (.keyword, .digit): state = .aggregatingIdentifier
			
		case (.aggregatingIdentifier, .identifier): break
		case (.aggregatingIdentifier, .combining): break
		case (.aggregatingIdentifier, .digit): break
			
		case (.periodOp, .op): break
		case (.periodOp, .openAngle): break
		case (.periodOp, .closeAngle): break
		case (.periodOp, .combining): break
		case (.periodOp, .period): break
			
		case (.aggregating(.multiSpace), .space): break
		case (.aggregating(tok), _): break
			
		case (.singleSpace, .space): state = .aggregating(.multiSpace)
			
		case (.singleOpenAngle, .questionMark), (.singleOpenAngle, .op), (.singleOpenAngle, .openAngle), (.singleOpenAngle, .closeAngle): fallthrough
		case (.singleCloseAngle, .questionMark), (.singleCloseAngle, .op), (.singleCloseAngle, .openAngle), (.singleCloseAngle, .closeAngle): fallthrough
		case (.singleQuestionMark, .questionMark), (.singleQuestionMark, .op), (.singleQuestionMark, .openAngle), (.singleQuestionMark, .closeAngle): state = startOp(scalar)
			
		case (.possibleOp(let f), .op), (.possibleOp(let f), .combining), (.possibleOp(let f), .questionMark), (.possibleOp(let f), .openAngle), (.possibleOp(let f), .closeAngle):
			state = f(scalar)
			if case .splitOp(let t, let length) = state {
				if scanner.scalars[start..<scanner.index].count > length {
					try scanner.backtrack(count: length)
					return Token<C>(tok: .op, slice: scanner.scalars[start..<scanner.index])
				} else {
					return Token<C>(tok: t, slice: scanner.scalars[start..<scanner.index])
				}
			}
			
		case (.possibleKeyword(let f), .identifier): state = f(scalar)
		case (.possibleKeyword(let f), .combining): state = f(scalar)
		case (.possibleKeyword(let f), .digit): state = f(scalar)
			
		case (.keywordOrPossibleKeyword(_, let f), .identifier): state = f(scalar)
		case (.keywordOrPossibleKeyword(_, let f), .combining): state = f(scalar)
		case (.keywordOrPossibleKeyword(_, let f), .digit): state = f(scalar)
			
		default:
			try scanner.backtrack()
			return Token<C>(tok: state.finalize(), slice: scanner.scalars[start..<scanner.index])
		}
	} while true } catch {
		return Token<C>(tok: state.finalize(), slice: scanner.scalars[start..<scanner.index])
	}
}

// Peek at the next scalar and classify the token to which it would belong. NOTE: this is only intended for calling from `nextToken` which aggregates scalars and further matches keywords from "other" globs.
func classify(_ scalar: UnicodeScalar) -> Tok {
	switch scalar {
	case "\n", "\r": return .endOfLine
		
	case " ": return .space
	case "\t": return .tab
	case "\"": return .quote
	case "{": return .openBrace
	case "}": return .closeBrace
	case "[": return .openBracket
	case "]": return .closeBracket
	case "(": return .openParen
	case ")": return .closeParen
	case "<": return .openAngle
	case ">": return .closeAngle
	case "\\": return .backslash
	case ":": return .colon
	case ",": return .comma
	case "#": return .hash
	case "$": return .dollar
	case ".": return .period
	case ";": return .semiColon
	case "@": return .at
	case "`": return .backtick
		
	case "?": return .questionMark
		
	case "a"..."z", "A"..."Z": fallthrough
	case "_": fallthrough
	case "\u{00a8}", "\u{00aa}", "\u{00ad}", "\u{00af}": fallthrough
	case "\u{00b2}"..."\u{00b5}", "\u{00b7}"..."\u{00ba}": fallthrough
	case "\u{00bc}"..."\u{00be}", "\u{00c0}"..."\u{00d6}": fallthrough
	case "\u{00d8}"..."\u{00f6}", "\u{00f8}"..."\u{00ff}": fallthrough
	case "\u{0100}"..."\u{02ff}", "\u{0370}"..."\u{167f}": fallthrough
	case "\u{1681}"..."\u{180d}", "\u{180f}"..."\u{1dbf}": fallthrough
	case "\u{1e00}"..."\u{1fff}", "\u{200b}"..."\u{200d}": fallthrough
	case "\u{202a}"..."\u{202e}", "\u{203f}"..."\u{2040}": fallthrough
	case "\u{2054}": fallthrough
	case "\u{2060}"..."\u{206f}", "\u{2070}"..."\u{20cf}": fallthrough
	case "\u{2100}"..."\u{218f}", "\u{2460}"..."\u{24ff}": fallthrough
	case "\u{2776}"..."\u{2793}", "\u{2c00}"..."\u{2dff}": fallthrough
	case "\u{2e80}"..."\u{2fff}", "\u{3004}"..."\u{3007}": fallthrough
	case "\u{3021}"..."\u{302f}", "\u{3031}"..."\u{303f}": fallthrough
	case "\u{3040}"..."\u{d7ff}", "\u{f900}"..."\u{fd3d}": fallthrough
	case "\u{fd40}"..."\u{fdcf}", "\u{fdf0}"..."\u{fe1f}": fallthrough
	case "\u{fe30}"..."\u{fe44}", "\u{fe47}"..."\u{fffd}": fallthrough
	case "\u{10000}"..."\u{1fffd}", "\u{20000}"..."\u{2fffd}": fallthrough
	case "\u{30000}"..."\u{3fffd}", "\u{40000}"..."\u{4fffd}": fallthrough
	case "\u{50000}"..."\u{5fffd}", "\u{60000}"..."\u{6fffd}": fallthrough
	case "\u{70000}"..."\u{7fffd}", "\u{80000}"..."\u{8fffd}": fallthrough
	case "\u{90000}"..."\u{9fffd}", "\u{a0000}"..."\u{afffd}": fallthrough
	case "\u{b0000}"..."\u{bfffd}", "\u{c0000}"..."\u{cfffd}": fallthrough
	case "\u{d0000}"..."\u{dfffd}", "\u{e0000}"..."\u{efffd}": return .identifier
		
	case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9": return .digit
		
	case "\u{0300}"..."\u{036f}", "\u{1dc0}"..."\u{1dff}": fallthrough
	case "\u{20d0}"..."\u{20ff}", "\u{fe20}"..."\u{fe2f}": return .combining
		
	case "/", "=", "-", "+", "!", "*", "%", "&": fallthrough
	case "|", "^", "~": fallthrough
	case "\u{00a1}"..."\u{00a7}", "\u{00a9}"..."\u{00ab}": fallthrough
	case "\u{00ac}"..."\u{00ae}", "\u{00b0}"..."\u{00b1}": fallthrough
	case "\u{00b6}"..."\u{00bb}", "\u{00bf}"..."\u{00d7}": fallthrough
	case "\u{00f7}": fallthrough
	case "\u{2016}"..."\u{2017}", "\u{2020}"..."\u{2027}": fallthrough
	case "\u{2030}"..."\u{203e}", "\u{2041}"..."\u{2053}": fallthrough
	case "\u{2055}"..."\u{205e}", "\u{2190}"..."\u{23ff}": fallthrough
	case "\u{2500}"..."\u{2775}", "\u{2794}"..."\u{2bff}": fallthrough
	case "\u{2e00}"..."\u{2e7f}", "\u{3001}"..."\u{3003}": fallthrough
	case "\u{3008}"..."\u{3030}": return .op
		
	case "\u{000b}", "\u{000c}", "\0": return .whitespace
		
	default: return .invalid
	}
}

func startOp(_ scalar: UnicodeScalar) -> LexerState {
	switch scalar {
	case "/":
		return LexerState.possibleOp {
			switch $0 {
			case "*": return LexerState.splitOp(.slashStar, 2)
			case "/": return LexerState.splitOp(.doubleSlash, 2)
			default: return startOp($0)
			}
		}
	case "*":
		return LexerState.possibleOp {
			$0 == "/" ? LexerState.splitOp(.starSlash, 2) : startOp($0)
		}
	default: return LexerState.possibleOp { startOp($0) }
	}
}

func startHash(_ scalar: UnicodeScalar) -> LexerState {
	return LexerState.possibleKeyword {
		switch $0 {
		case "i":
			return LexerState.possibleKeyword {
				$0 == "f" ? .keyword(.hashIfKeyword) : .aggregating(.identifier)
			}
		case "e":
			return LexerState.possibleKeyword {
				switch $0 {
				case "l":
					return LexerState.possibleKeyword {
						$0 == "s" ? LexerState.possibleKeyword {
							$0 == "e" ? LexerState.keywordOrPossibleKeyword(.hashElseKeyword) {
								$0 == "i" ? LexerState.possibleKeyword {
									$0 == "f" ? .keyword(.hashElseifKeyword) : .aggregating(.identifier)
								} : .aggregating(.identifier)
							} : .aggregating(.identifier)
						} : .aggregating(.identifier)
					}
				case "n":
					return LexerState.possibleKeyword {
						$0 == "d" ? LexerState.possibleKeyword {
							$0 == "i" ? LexerState.possibleKeyword {
								$0 == "f" ? .keyword(.hashEndifKeyword) : .aggregating(.identifier)
							} : .aggregating(.identifier)
						} : .aggregating(.identifier)
					}
				default: return .aggregating(.identifier)
				}
			}
		default: return .aggregating(.identifier)
		}
	}
}

func startKeyword(_ scalar: UnicodeScalar) -> LexerState {
	switch scalar {
	case "c":
		return LexerState.possibleKeyword {
			$0 == "a" ? LexerState.possibleKeyword {
				$0 == "s" ? LexerState.possibleKeyword {
					$0 == "e" ? .keyword(.caseKeyword) : .aggregating(.identifier)
				} : .aggregating(.identifier)
			} : .aggregating(.identifier)
		}
	case "d":
		return LexerState.possibleKeyword {
			$0 == "e" ? LexerState.possibleKeyword {
				$0 == "f" ? LexerState.possibleKeyword {
					$0 == "a" ? LexerState.possibleKeyword {
						$0 == "u" ? LexerState.possibleKeyword {
							$0 == "l" ? LexerState.possibleKeyword {
								$0 == "t" ? .keyword(.defaultKeyword) : .aggregating(.identifier)
							} : .aggregating(.identifier)
						} : .aggregating(.identifier)
					} : .aggregating(.identifier)
				} : .aggregating(.identifier)
			} : .aggregating(.identifier)
		}
	case "s":
		return LexerState.possibleKeyword {
			$0 == "w" ? LexerState.possibleKeyword {
				$0 == "i" ? LexerState.possibleKeyword {
					$0 == "t" ? LexerState.possibleKeyword {
						$0 == "c" ? LexerState.possibleKeyword {
							$0 == "h" ? .keyword(.switchKeyword) : .aggregating(.identifier)
						} : .aggregating(.identifier)
					} : .aggregating(.identifier)
				} : .aggregating(.identifier)
			} : .aggregating(.identifier)
		}
	default: return .aggregating(.identifier)
	}
}

struct ValidIndent {
	let tagger: WhitespaceTagger
	let column: Int
	init(_ tagger: WhitespaceTagger, _ column: Int) {
		self.tagger = tagger
		self.column = column
	}
}

func ~=(test: ValidIndent, token: Tok) -> Bool {
	switch (token, test.tagger.stack.last) {
	case (.slashStar, .some(.switchScope)): fallthrough
	case (.doubleSlash, .some(.switchScope)):
		if test.column == test.tagger.expectedWidthForIndent(endingWith: token) - test.tagger.indentWidth() {
			return true
		}
		fallthrough
	default: return test.column == test.tagger.expectedWidthForIndent(endingWith: token)
	}
}

struct UniqueScope {
	let scope: Scope
	init(_ scope: Scope) {
		self.scope = scope
	}
}

func ~=(test: UniqueScope, array: Array<Scope>) -> Bool {
	return array.reduce(0) { $1 == test.scope ? $0 + 1 : $0 } == 1
}

struct IndentToken {
	let style: IndentationStyle
	init(_ style: IndentationStyle) {
		self.style = style
	}
}

func ~=(left: IndentToken, right: Tok) -> Bool {
	switch left.style {
	case .tabs: return right == .tab
	case .spaces: return right == .space
	}
}

struct TopScope {
	let scope: Scope
	init(_ scope: Scope) {
		self.scope = scope
	}
}

func ~=(test: TopScope, array: Array<Scope>) -> Bool {
	return array.last == test.scope
}

typealias MatchBuffer = (UnicodeScalar, UnicodeScalar, UnicodeScalar, UnicodeScalar, UnicodeScalar, UnicodeScalar, UnicodeScalar, UnicodeScalar)
func match(first: inout MatchBuffer, second: inout MatchBuffer) -> Bool {
	return withUnsafePointers(&first, &second) { (firstPtr, secondPtr) -> Bool in
		memcmp(UnsafePointer<Void>(firstPtr), UnsafePointer<Void>(secondPtr), sizeof(MatchBuffer.self)) == 0
	}
}
