//
//  CwlWhitespaceTaggingTests.swift
//  CwlWhitespaceTaggingTests
//
//  Created by Matt Gallagher on 2016/06/18.
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

import XCTest

class CwlWhitespaceTaggingTests: XCTestCase {
	func testParseEmpty() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parse(line: "")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testParseSingleSpace() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parse(line: " ")
		XCTAssert(regions == [TaggedRegion(start: 0, end: 1, tag: .incorrectIndent, expected: 0)])
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testParseNewline() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parse(line: "\n")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testParseBlockCommentNoNewline() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parse(line: "//  This is a comment")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testParseBlockCommentWithNewline() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parse(line: "// This is a comment\n")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testParseBlockCommentWithLeadingSpace() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parse(line: "  // This is a comment\n")
		XCTAssert(regions == [TaggedRegion(start: 0, end: 2, tag: .incorrectIndent, expected: 0)])
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testParseBodyText() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parse(line: "The quick brown fox.")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testParseBodyTextWithLeadingTabAndNewline() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parse(line: "\tThe quick brown fox.\n")
		XCTAssert(regions == [TaggedRegion(start: 0, end: 1, tag: .incorrectIndent, expected: 0)])
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testParseMultipleSpaces() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parse(line: "The quick  brown fox.")
		XCTAssert(regions == [TaggedRegion(start: 9, end: 11, tag: .multipleSpaces, expected: 1)])
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testTrailingWhitespace() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parse(line: "A \n")
		XCTAssert(regions == [TaggedRegion(start: 1, end: 2, tag: .unexpectedWhitespace, expected: 0)])
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testMultilineCommentWithDoubleSpace() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parse(line: "Comment /* something  **/")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testUnclosedMultilineComment() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parse(line: "Comment /* something ")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack == [.multilineComment])

		let regions2 = tagger.parse(line: "   */ end comment")
		XCTAssert(regions2.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testUnclosedParenthetical() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parse(line: "(")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack == [.paren])

		let regions2 = tagger.parse(line: ")")
		XCTAssert(regions2.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testUnclosedBrace() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parse(line: "{")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack == [.block])

		let regions2 = tagger.parse(line: "}")
		XCTAssert(regions2.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testLiteral() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parse(line: "Some \"literal  with  double  spaces\"")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testBraceSpace() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parse(line: "let o = OnDelete {x = true}")
		XCTAssert(regions == [TaggedRegion(start: 18, end: 18, tag: .missingSpace, expected: 1), TaggedRegion(start: 26, end: 26, tag: .missingSpace, expected: 1)])
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testTernary() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parse(line: "let x = y > 0 ? y : 0")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testLiteralInterpolationNesting() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parse(line: "body \"literal ignore dbl space  \\(interpolation nested paren(\"nestedLiteral ignore dbl space  dummy paren)\" back to interpolation  flag dbl space) outside paren) literal  ignore dbl space\" all scopes closed")
		XCTAssert(regions.count == 1)
		XCTAssert(regions == [TaggedRegion(start: 129, end: 131, tag: .multipleSpaces, expected: 1)])
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testSwitch() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parse(line: "switch a {")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger.stack == [.switchScope, .block])
		
		let regions2 = tagger.parse(line: "case one:")
		XCTAssert(regions2.isEmpty)
		XCTAssert(tagger.stack == [.switchScope, .block])
		
		let regions3 = tagger.parse(line: "\tmultiline")
		XCTAssert(regions3.isEmpty)
		XCTAssert(tagger.stack == [.switchScope, .block])
		
		let regions4 = tagger.parse(line: "case two: single line")
		XCTAssert(regions4.isEmpty)
		XCTAssert(tagger.stack == [.switchScope, .block])
		
		let regions5 = tagger.parse(line: "default: break")
		XCTAssert(regions5.isEmpty)
		XCTAssert(tagger.stack == [.switchScope, .block])
		
		let regions6 = tagger.parse(line: "}")
		XCTAssert(regions6.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testEnum() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parse(line: "enum a {")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger.stack == [.block])
		
		let regions2 = tagger.parse(line: "\tcase one")
		XCTAssert(regions2.isEmpty)
		XCTAssert(tagger.stack == [.block])
		
		let regions3 = tagger.parse(line: "\tcase two")
		XCTAssert(regions3.isEmpty)
		XCTAssert(tagger.stack == [.block])
		
		let regions4 = tagger.parse(line: "}")
		XCTAssert(regions4.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testClass() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parse(line: "class TestClass: TestSuperclass {\n")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger.stack == [.block])
		
		let regions2 = tagger.parse(line: "\tfunc testMethod() {\n")
		XCTAssert(regions2.isEmpty)
		XCTAssert(tagger.stack == [.block, .block])
		
		let regions3 = tagger.parse(line: "\t\tvar someVar = someValue\n")
		XCTAssert(regions3.isEmpty)
		XCTAssert(tagger.stack == [.block, .block])
		
		let regions4 = tagger.parse(line: "\t\tsomeValue.doSomething()\n")
		XCTAssert(regions4.isEmpty)
		XCTAssert(tagger.stack == [.block, .block])
		
		let regions5 = tagger.parse(line: "\t\t#if someTest()\n")
		XCTAssert(regions5.isEmpty)
		XCTAssert(tagger.stack == [.block, .block, .hash])
		
		let regions6 = tagger.parse(line: "\t\t\tsomeValue.doSomethingElse()\n")
		XCTAssert(regions6.isEmpty)
		XCTAssert(tagger.stack == [.block, .block, .hash])
		
		let regions7 = tagger.parse(line: "\t\t#endif\n")
		XCTAssert(regions7.isEmpty)
		XCTAssert(tagger.stack == [.block, .block])
		
		let regions8 = tagger.parse(line: "\t}\n")
		XCTAssert(regions8.isEmpty)
		XCTAssert(tagger.stack == [.block])
		
		let regions9 = tagger.parse(line: "\tvar t = s\n")
		XCTAssert(regions9.isEmpty)
		XCTAssert(tagger.stack == [.block])
		
		let regions10 = tagger.parse(line: "}")
		XCTAssert(regions10.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testIndentNesting() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parse(line: "a({")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger.stack == [.shadowedParen, .block])

		let regions2 = tagger.parse(line: "\tb")
		XCTAssert(regions2.isEmpty)
		XCTAssert(tagger.stack == [.shadowedParen, .block])

		let regions3 = tagger.parse(line: "}, c, {")
		XCTAssert(regions3.isEmpty)
		XCTAssert(tagger.stack == [.shadowedParen, .block])

		let regions4 = tagger.parse(line: "\td")
		XCTAssert(regions4.isEmpty)
		XCTAssert(tagger.stack == [.shadowedParen, .block])

		let regions5 = tagger.parse(line: "}) {(")
		XCTAssert(regions5 == [TaggedRegion(start: 4, end: 4, tag: .missingSpace, expected: 1)])
		XCTAssert(tagger.stack == [.shadowedBlock, .paren])

		let regions6 = tagger.parse(line: "\te")
		XCTAssert(regions6.isEmpty)
		XCTAssert(tagger.stack == [.shadowedBlock, .paren])

		let regions7 = tagger.parse(line: ") }")
		XCTAssert(regions7.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testBraces() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parse(line: "a.map{$0}")
		XCTAssert(tagger.stack.isEmpty)
		XCTAssert(regions1 == [TaggedRegion(start: 5, end: 5, tag: .missingSpace, expected: 1), TaggedRegion(start: 6, end: 6, tag: .missingSpace, expected: 1), TaggedRegion(start: 8, end: 8, tag: .missingSpace, expected: 1)])
	}
}
