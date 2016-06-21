//
//  CwlWhitespaceTests.swift
//  CwlWhitespaceTests
//
//  Created by Matt Gallagher on 2016/06/18.
//  Copyright © 2016 Matt Gallagher. All rights reserved.
//

import XCTest

class CwlWhitespaceTests: XCTestCase {
	func testParseEmpty() {
		var scanner = ScalarScanner(scalars: "".unicodeScalars, context: ParseContext())
		do { try scanner.parseLine() } catch { XCTFail() }
		XCTAssert(scanner.context.flagged.count == 0)
		XCTAssert(scanner.context.stack.count == 1)
		XCTAssert(scanner.context.stack[0].tag == .indent)
	}
	func testParseSingleSpace() {
		var scanner = ScalarScanner(scalars: " ".unicodeScalars, context: ParseContext())
		do { try scanner.parseLine() } catch { XCTFail() }
		XCTAssert(scanner.context.flagged.count == 1)
		XCTAssert(scanner.context.flagged[0] == TaggedRegion(line: 0, start: 0, end: 1, tag: .whitespace))
		XCTAssert(scanner.context.stack.count == 1)
		XCTAssert(scanner.context.stack[0].tag == .indent)
	}
	func testParseNewline() {
		var scanner = ScalarScanner(scalars: "\n".unicodeScalars, context: ParseContext())
		do { try scanner.parseLine() } catch { XCTFail() }
		XCTAssert(scanner.context.flagged.count == 0)
		XCTAssert(scanner.context.stack.count == 1)
		XCTAssert(scanner.context.stack[0].tag == .indent)
	}
	func testParseBlockCommentNoNewline() {
		var scanner = ScalarScanner(scalars: "// This is a comment".unicodeScalars, context: ParseContext())
		do { try scanner.parseLine() } catch { XCTFail() }
		XCTAssert(scanner.context.flagged.count == 0)
		XCTAssert(scanner.context.stack.count == 1)
		XCTAssert(scanner.context.stack[0].tag == .indent)
	}
	func testParseBlockCommentWithNewline() {
		var scanner = ScalarScanner(scalars: "// This is a comment\n".unicodeScalars, context: ParseContext())
		do { try scanner.parseLine() } catch { XCTFail() }
		XCTAssert(scanner.context.flagged.count == 0)
		XCTAssert(scanner.context.stack.count == 1)
		XCTAssert(scanner.context.stack[0].tag == .indent)
	}
	func testParseBlockCommentWithLeadingSpace() {
		var scanner = ScalarScanner(scalars: "  // This is a comment\n".unicodeScalars, context: ParseContext())
		do { try scanner.parseLine() } catch { XCTFail() }
		XCTAssert(scanner.context.flagged.count == 1)
		XCTAssert(scanner.context.flagged[0] == TaggedRegion(line: 0, start: 0, end: 2, tag: .indent, expected: 0))
		XCTAssert(scanner.context.stack.count == 1)
		XCTAssert(scanner.context.stack[0].tag == .indent)
	}
	func testParseBodyText() {
		var scanner = ScalarScanner(scalars: "The quick brown fox.".unicodeScalars, context: ParseContext())
		do { try scanner.parseLine() } catch { XCTFail() }
		XCTAssert(scanner.context.flagged.count == 0)
		XCTAssert(scanner.context.stack.count == 1)
		XCTAssert(scanner.context.stack[0].tag == .indent)
	}
	func testParseBodyTextWithLeadingTabAndNewline() {
		var scanner = ScalarScanner(scalars: "\tThe quick brown fox.\n".unicodeScalars, context: ParseContext())
		do { try scanner.parseLine() } catch { XCTFail() }
		XCTAssert(scanner.context.flagged.count == 1)
		XCTAssert(scanner.context.flagged[0] == TaggedRegion(line: 0, start: 0, end: 1, tag: .indent, expected: 0))
		XCTAssert(scanner.context.stack.count == 1)
		XCTAssert(scanner.context.stack[0].tag == .indent)
	}
	func testParseMultipleSpaces() {
		var scanner = ScalarScanner(scalars: "The quick  brown fox.".unicodeScalars, context: ParseContext())
		do { try scanner.parseLine() } catch { XCTFail() }
		XCTAssert(scanner.context.flagged.count == 1)
		XCTAssert(scanner.context.flagged[0] == TaggedRegion(line: 0, start: 9, end: 11, tag: .whitespace, expected: 1))
		XCTAssert(scanner.context.stack.count == 1)
		XCTAssert(scanner.context.stack[0].tag == .indent)
	}
	func testCRLF() {
		var scanner = ScalarScanner(scalars: "A\r\n".unicodeScalars, context: ParseContext())
		do { try scanner.parseLine() } catch { XCTFail() }
		XCTAssert(scanner.context.flagged.count == 1)
		XCTAssert(scanner.context.flagged[0] == TaggedRegion(line: 0, start: 1, end: 2, tag: .whitespace, expected: 0))
		XCTAssert(scanner.context.stack.count == 1)
		XCTAssert(scanner.context.stack[0].tag == .indent)
	}
}
