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
	func testEmpty() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testSingleSpace() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine(" ")
		XCTAssert(regions == [TaggedRegion(start: 0, end: 1, tag: .incorrectIndent, expected: 0)])
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testNewline() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("\n")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testBlockCommentNoNewline() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("//  This is a comment")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testBlockCommentWithNewline() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("// This is a comment\n")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testBlockCommentWithLeadingSpace() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("  // This is a comment\n")
		XCTAssert(regions == [TaggedRegion(start: 0, end: 2, tag: .incorrectIndent, expected: 0)])
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testBodyText() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("The quick brown fox.")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testBodyTextWithLeadingTabAndNewline() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("\tThe quick brown fox.\n")
		XCTAssert(regions == [TaggedRegion(start: 0, end: 1, tag: .incorrectIndent, expected: 0)])
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testMultipleSpaces() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("The quick  brown fox.")
		XCTAssert(regions == [TaggedRegion(start: 9, end: 11, tag: .multipleSpaces, expected: 1)])
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testTrailingWhitespace() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("A \n")
		XCTAssert(regions == [TaggedRegion(start: 1, end: 2, tag: .unexpectedWhitespace, expected: 0)])
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testMultilineCommentWithDoubleSpace() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("Comment /* something  **/")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testUnclosedMultilineComment() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("Comment /* something ")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack == [.comment])

		let regions2 = tagger.parseLine("   */ end comment")
		XCTAssert(regions2.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testUnclosedParenthetical() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("(")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack == [.paren])

		let regions2 = tagger.parseLine(")")
		XCTAssert(regions2.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testUnclosedBrace() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("{")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack == [.block])

		let regions2 = tagger.parseLine("}")
		XCTAssert(regions2.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testLiteral() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("Some \"literal  with  double  spaces\"")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testBraceSpace() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("let o = OnDelete {x = true}")
		XCTAssert(regions == [TaggedRegion(start: 18, end: 18, tag: .missingSpace, expected: 1), TaggedRegion(start: 26, end: 26, tag: .missingSpace, expected: 1)])
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testShadowedAndEmptyBraces() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parseLine("do { repeat {")
		XCTAssert(tagger.stack == [.shadowedBlock, .block])
		XCTAssert(regions1.isEmpty)

		let regions2 = tagger.parseLine("\ttry someFunction()")
		XCTAssert(tagger.stack == [.shadowedBlock, .block])
		XCTAssert(regions2.isEmpty)

		let regions3 = tagger.parseLine("} while true } catch {}")
		XCTAssert(regions3.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testTernary() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("let x = y > 0 ? y : 0")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testLiteralInterpolationNesting() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("body \"literal ignore dbl space  \\(interpolation nested paren(\"nestedLiteral ignore dbl space  dummy paren)\" back to interpolation  flag dbl space) outside paren) literal  ignore dbl space\" all scopes closed")
		XCTAssert(regions.count == 1)
		XCTAssert(regions == [TaggedRegion(start: 129, end: 131, tag: .multipleSpaces, expected: 1)])
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testDoubleBackslashEscaping() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("let regions = tagger.parseLine(\"body \\\"literal ignore dbl space  \\\\(interpolation nested paren(\\\"nestedLiteral ignore dbl space  dummy paren)\\\" back to interpolation  flag dbl space) outside paren) literal  ignore dbl space\\\" all scopes closed\")")
		XCTAssert(regions.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testSwitch() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parseLine("switch a {")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger.stack == [.switchScope])
		
		let regions2 = tagger.parseLine("// Non-indented comment")
		XCTAssert(regions2.isEmpty)
		XCTAssert(tagger.stack == [.switchScope])
		
		let regions3 = tagger.parseLine("case one:")
		XCTAssert(regions3.isEmpty)
		XCTAssert(tagger.stack == [.switchScope])
		
		let regions4 = tagger.parseLine("\t// Indented comment")
		XCTAssert(regions4.isEmpty)
		XCTAssert(tagger.stack == [.switchScope])
		
		let regions5 = tagger.parseLine("\tmultiline")
		XCTAssert(regions5.isEmpty)
		XCTAssert(tagger.stack == [.switchScope])
		
		let regions6 = tagger.parseLine("case two: single line")
		XCTAssert(regions6.isEmpty)
		XCTAssert(tagger.stack == [.switchScope])
		
		let regions7 = tagger.parseLine("default: break")
		XCTAssert(regions7.isEmpty)
		XCTAssert(tagger.stack == [.switchScope])
		
		let regions8 = tagger.parseLine("}")
		XCTAssert(regions8.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testEnum() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parseLine("enum a {")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger.stack == [.block])
		
		let regions2 = tagger.parseLine("\tcase one")
		XCTAssert(regions2.isEmpty)
		XCTAssert(tagger.stack == [.block])
		
		let regions3 = tagger.parseLine("\tcase two")
		XCTAssert(regions3.isEmpty)
		XCTAssert(tagger.stack == [.block])
		
		let regions4 = tagger.parseLine("}")
		XCTAssert(regions4.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testClass() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parseLine("class TestClass: TestSuperclass {\n")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger.stack == [.block])
		
		let regions2 = tagger.parseLine("\tfunc testMethod() {\n")
		XCTAssert(regions2.isEmpty)
		XCTAssert(tagger.stack == [.block, .block])
		
		let regions3 = tagger.parseLine("\t\tvar someVar = someValue\n")
		XCTAssert(regions3.isEmpty)
		XCTAssert(tagger.stack == [.block, .block])
		
		let regions4 = tagger.parseLine("\t\tsomeValue.doSomething()\n")
		XCTAssert(regions4.isEmpty)
		XCTAssert(tagger.stack == [.block, .block])
		
		let regions5 = tagger.parseLine("\t\t#if someTest()\n")
		XCTAssert(regions5.isEmpty)
		XCTAssert(tagger.stack == [.block, .block, .hash])
		
		let regions6 = tagger.parseLine("\t\t\tsomeValue.doSomethingElse()\n")
		XCTAssert(regions6.isEmpty)
		XCTAssert(tagger.stack == [.block, .block, .hash])
		
		let regions12 = tagger.parseLine("\t\t#else\n")
		XCTAssert(regions12.isEmpty)
		XCTAssert(tagger.stack == [.block, .block, .hash])
		
		let regions11 = tagger.parseLine("\t\t\tsomeValue.doSomethingElse()\n")
		XCTAssert(regions11.isEmpty)
		XCTAssert(tagger.stack == [.block, .block, .hash])
		
		let regions7 = tagger.parseLine("\t\t#endif\n")
		XCTAssert(regions7.isEmpty)
		XCTAssert(tagger.stack == [.block, .block])
		
		let regions8 = tagger.parseLine("\t}\n")
		XCTAssert(regions8.isEmpty)
		XCTAssert(tagger.stack == [.block])
		
		let regions9 = tagger.parseLine("\tvar t = s\n")
		XCTAssert(regions9.isEmpty)
		XCTAssert(tagger.stack == [.block])
		
		let regions10 = tagger.parseLine("}")
		XCTAssert(regions10.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}

	func testNilCoalescing() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parseLine("if let dli_sname = info.dli_sname, _ = String(validatingUTF8: dli_sname) {")
		let regions2 = tagger.parseLine("\treturn Int(address - (UInt(bitPattern: info.dli_saddr) ?? 0))")
		let regions3 = tagger.parseLine("}")
		XCTAssert(regions1.isEmpty)
		XCTAssert(regions2.isEmpty)
		XCTAssert(regions3.isEmpty)
	}
	
	func testSpaceInsteadOfTabs() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parseLine("{")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger.stack == [.block])

		let regions2 = tagger.parseLine(" b")
		XCTAssert(regions2 == [TaggedRegion(start: 0, end: 1, tag: .incorrectIndent, expected: 1)])
		XCTAssert(tagger.stack == [.block])

		let regions3 = tagger.parseLine("}")
		XCTAssert(regions3.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testSpaceInsteadOfTabs2() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parseLine("{")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger.stack == [.block])

		let regions4 = tagger.parseLine("\t{")
		XCTAssert(regions4.isEmpty)
		XCTAssert(tagger.stack == [.block, .block])

		let regions2 = tagger.parseLine("\t b")
		XCTAssert(regions2 == [TaggedRegion(start: 0, end: 2, tag: .incorrectIndent, expected: 2)])
		XCTAssert(tagger.stack == [.block, .block])

		let regions3 = tagger.parseLine("\t}")
		XCTAssert(regions3.isEmpty)
		XCTAssert(tagger.stack == [.block])

		let regions5 = tagger.parseLine("}")
		XCTAssert(regions5.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testSpaceInsteadOfTabs3() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parseLine("{")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger.stack == [.block])

		let regions4 = tagger.parseLine("\t{")
		XCTAssert(regions4.isEmpty)
		XCTAssert(tagger.stack == [.block, .block])

		let regions2 = tagger.parseLine(" \tb")
		XCTAssert(regions2 == [TaggedRegion(start: 0, end: 2, tag: .incorrectIndent, expected: 2)])
		XCTAssert(tagger.stack == [.block, .block])

		let regions3 = tagger.parseLine("\t}")
		XCTAssert(regions3.isEmpty)
		XCTAssert(tagger.stack == [.block])

		let regions5 = tagger.parseLine("}")
		XCTAssert(regions5.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testIndentNesting() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parseLine("a({")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger.stack == [.shadowedParen, .block])

		let regions2 = tagger.parseLine("\tb")
		XCTAssert(regions2.isEmpty)
		XCTAssert(tagger.stack == [.shadowedParen, .block])

		let regions3 = tagger.parseLine("}, c, {")
		XCTAssert(regions3.isEmpty)
		XCTAssert(tagger.stack == [.shadowedParen, .block])

		let regions4 = tagger.parseLine("\td")
		XCTAssert(regions4.isEmpty)
		XCTAssert(tagger.stack == [.shadowedParen, .block])

		let regions5 = tagger.parseLine("}) {(")
		XCTAssert(regions5 == [TaggedRegion(start: 4, end: 4, tag: .missingSpace, expected: 1)])
		XCTAssert(tagger.stack == [.shadowedBlock, .paren])

		let regions6 = tagger.parseLine("\te")
		XCTAssert(regions6.isEmpty)
		XCTAssert(tagger.stack == [.shadowedBlock, .paren])

		let regions7 = tagger.parseLine(") }")
		XCTAssert(regions7.isEmpty)
		XCTAssert(tagger.stack.isEmpty)
	}
	
	func testBraces() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parseLine("a.map{$0}")
		XCTAssert(tagger.stack.isEmpty)
		XCTAssert(regions1 == [TaggedRegion(start: 5, end: 5, tag: .missingSpace, expected: 1), TaggedRegion(start: 6, end: 6, tag: .missingSpace, expected: 1), TaggedRegion(start: 8, end: 8, tag: .missingSpace, expected: 1)])
	}
	
	func testMisplacedComma() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parseLine("let x = (0 ,0)")
		XCTAssert(tagger.stack.isEmpty)
		XCTAssert(regions1 == [TaggedRegion(start: 10, end: 11, tag: .unexpectedWhitespace, expected: 0), TaggedRegion(start: 12, end: 12, tag: .missingSpace, expected: 1)])

		var tagger2 = WhitespaceTagger()
		let regions2 = tagger2.parseLine("let x = (0  ,0)")
		XCTAssert(tagger2.stack.isEmpty)
		XCTAssert(regions2 == [TaggedRegion(start: 10, end: 12, tag: .multipleSpaces, expected: 1), TaggedRegion(start: 11, end: 12, tag: .unexpectedWhitespace, expected: 0), TaggedRegion(start: 13, end: 13, tag: .missingSpace, expected: 1)])
	}
	
	func testSpaceFollowingParen() {
		var tagger = WhitespaceTagger()
		let regions = tagger.parseLine("func someFunction( param: Type ){")
		XCTAssert(tagger.stack == [.block])
		XCTAssert(regions == [TaggedRegion(start: 18, end: 19, tag: .unexpectedWhitespace, expected: 0), TaggedRegion(start: 30, end: 31, tag: .unexpectedWhitespace, expected: 0), TaggedRegion(start: 32, end: 32, tag: .missingSpace, expected: 1)])
	}

	func testSpaceProblems() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parseLine("(param:Type)")
		XCTAssert(regions1 == [TaggedRegion(start: 7, end: 7, tag: .missingSpace, expected: 1)])

		let regions2 = tagger.parseLine("var (a,b) = ( c, d )")
		XCTAssert(regions2 == [TaggedRegion(start: 7, end: 7, tag: .missingSpace, expected: 1), TaggedRegion(start: 13, end: 14, tag: .unexpectedWhitespace, expected: 0), TaggedRegion(start: 18, end: 19, tag: .unexpectedWhitespace, expected: 0)])

		let regions3 = tagger.parseLine("(param : Type)")
		XCTAssert(regions3 == [TaggedRegion(start: 6, end: 7, tag: .unexpectedWhitespace, expected: 0)])

		let regions4 = tagger.parseLine("(param :Type)")
		XCTAssert(regions4 == [TaggedRegion(start: 6, end: 7, tag: .unexpectedWhitespace, expected: 0), TaggedRegion(start: 8, end: 8, tag: .missingSpace, expected: 1)])
	}

	func testPrefixPostfixInfix() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parseLine("a+b! - -c??d")
		XCTAssert(regions1 == [TaggedRegion(start: 1, end: 1, tag: .missingSpace, expected: 1), TaggedRegion(start: 2, end: 2, tag: .missingSpace, expected: 1), TaggedRegion(start: 9, end: 9, tag: .missingSpace, expected: 1), TaggedRegion(start: 11, end: 11, tag: .missingSpace, expected: 1)])
	}

	func testDotOperators() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parseLine("a.b...c.d..<(e + f * g! - h? & _ ^ i << j >> k < l > m)..>7")
		XCTAssert(regions1.isEmpty)

		let regions2 = tagger.parseLine("a.b ... c.d ..< e")
		XCTAssert(regions2 == [TaggedRegion(start: 3, end: 4, tag: .unexpectedWhitespace, expected: 0), TaggedRegion(start: 7, end: 8, tag: .unexpectedWhitespace, expected: 0), TaggedRegion(start: 11, end: 12, tag: .unexpectedWhitespace, expected: 0), TaggedRegion(start: 15, end: 16, tag: .unexpectedWhitespace, expected: 0)])

		let regions3 = tagger.parseLine("(a.b)...(c.d) ... -e...(-f)")
		XCTAssert(regions3 == [TaggedRegion(start: 13, end: 14, tag: .unexpectedWhitespace, expected: 0), TaggedRegion(start: 17, end: 18, tag: .unexpectedWhitespace, expected: 0)])

		let regions4 = tagger.parseLine("case \"a\"...\"z\", \"A\"...\"Z\": fallthrough")
		XCTAssert(regions4.isEmpty)
	}
	
	func testSingleQuote() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parseLine("let x = \"'\"")
		XCTAssert(regions1.isEmpty)

		let regions2 = tagger.parseLine("let x = 'y'")
		XCTAssert(regions2 == [TaggedRegion(start: 8, end: 9, tag: .invalidCharacter, expected: 0), TaggedRegion(start: 10, end: 11, tag: .invalidCharacter, expected: 0)])
	}

	func testGenericParams() {
		var tagger = WhitespaceTagger()
		let regions1 = tagger.parseLine("let x: A<B>")
		XCTAssert(regions1.isEmpty)

		let regions2 = tagger.parseLine("func A<B>() {}")
		XCTAssert(regions2.isEmpty)

		let regions3 = tagger.parseLine("func A< B >() {}")
		XCTAssert(regions3 == [TaggedRegion(start: 7, end: 8, tag: .unexpectedWhitespace, expected: 0), TaggedRegion(start: 9, end: 10, tag: .unexpectedWhitespace, expected: 0)])
	}
	
	func testKeywordAsIdentifier() {
		var tagger = WhitespaceTagger()
		_ = tagger.parseLine("class A {")
		_ = tagger.parseLine("\tfunc B() {")
		let regions1 = tagger.parseLine("\t\tSome.case.default.switch.identifier {")
		XCTAssert(regions1.isEmpty)
	}
	
	func testPrefix() {
		var tagger1 = WhitespaceTagger()
		let regions1 = tagger1.parseLine("let a = [-1, b!]")
		XCTAssert(regions1.isEmpty)

		var tagger2 = WhitespaceTagger()
		let regions2 = tagger2.parseLine("let a = (-1, b?)")
		XCTAssert(regions2.isEmpty)
		
		var tagger3 = WhitespaceTagger()
		let regions3 = tagger3.parseLine("let a = [.hello]")
		XCTAssert(regions3.isEmpty)

		var tagger4 = WhitespaceTagger()
		let regions4 = tagger4.parseLine("let a = (.hello)")
		XCTAssert(regions4.isEmpty)

		var tagger5 = WhitespaceTagger()
		let regions5 = tagger5.parseLine("let a = .hello")
		XCTAssert(regions5.isEmpty)

		var tagger6 = WhitespaceTagger()
		let regions6 = tagger6.parseLine("let a = -5")
		XCTAssert(regions6.isEmpty)
	}
	
	func testNestedGeneric() {
		var tagger1 = WhitespaceTagger()
		let regions1 = tagger1.parseLine("let t = Alpha<Beta<Gamma>>()")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger1.stack.isEmpty)
		
		var tagger2 = WhitespaceTagger()
		let regions2 = tagger2.parseLine("let t = a >> b")
		XCTAssert(regions2.isEmpty)
		XCTAssert(tagger2.stack.isEmpty)
	}
	
	func testOptionalParam() {
		var tagger1 = WhitespaceTagger()
		let regions1 = tagger1.parseLine("let t = (String?, String?) -> Void")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger1.stack.isEmpty)
	}
	
	func testPostfixDot() {
		var tagger1 = WhitespaceTagger()
		let regions1 = tagger1.parseLine("let t = alpha!.beta()")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger1.stack.isEmpty)
	}
	
	func testCloseGenericWithQuestionMark() {
		var tagger1 = WhitespaceTagger()
		let regions1 = tagger1.parseLine("weak var weakInput: SignalInput<Int>? = nil")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger1.stack.isEmpty)
	}
	
	func testInvokeConditionalOptionalFunction() {
		var tagger1 = WhitespaceTagger()
		let regions1 = tagger1.parseLine("let t = a?()")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger1.stack.isEmpty)
	}

	func testInvokeForceOptionalFunction() {
		var tagger1 = WhitespaceTagger()
		let regions1 = tagger1.parseLine("let t = a!()")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger1.stack.isEmpty)
	}

	func testBackticks() {
		var tagger1 = WhitespaceTagger()
		let regions1 = tagger1.parseLine("var `default`: String { get }")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger1.stack.isEmpty)
	}

	func testCaseScenario() {
		var tagger1 = WhitespaceTagger()
		let regions1 = tagger1.parseLine("SomeClass<String?>")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger1.stack.isEmpty)
	}

	func testOptionalArray() {
		var tagger1 = WhitespaceTagger()
		let regions1 = tagger1.parseLine("let x = a?[0]")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger1.stack.isEmpty)
	}

	func testMultilineArray() {
		var tagger1 = WhitespaceTagger()
		let regions1 = tagger1.parseLine("let x = [\n")
		let regions2 = tagger1.parseLine("\tfirst,\n")
		let regions3 = tagger1.parseLine("\tsecond\n")
		let regions4 = tagger1.parseLine("]\n")
		XCTAssert(regions1.isEmpty)
		XCTAssert(regions2.isEmpty)
		XCTAssert(regions3.isEmpty)
		XCTAssert(regions4.isEmpty)
		XCTAssert(tagger1.stack.isEmpty)
	}
	
	func testMultilineFunction() {
		var tagger1 = WhitespaceTagger()
		let regions1 = tagger1.parseLine("Top.construct(\n")
		let regions2 = tagger1.parseLine("\tSecond.construct(\n")
		let regions3 = tagger1.parseLine("\t\tControl.enabled <-- viewModel.selectionOutput.map { !$0.isEmpty }\n")
		let regions4 = tagger1.parseLine("\t)\n")
		let regions5 = tagger1.parseLine(")\n")
		XCTAssert(regions1.isEmpty)
		XCTAssert(regions2.isEmpty)
		XCTAssert(regions3.isEmpty)
		XCTAssert(regions4.isEmpty)
		XCTAssert(regions5.isEmpty)
		XCTAssert(tagger1.stack.isEmpty)
	}
	
	func testSelector() {
		var tagger1 = WhitespaceTagger()
		let regions1 = tagger1.parseLine("let s = #selector(NSApplicationDelegate.application(_:printFiles:withSettings:showPrintPanels:))")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger1.stack.isEmpty)
	}
	
	func testAtAvailable() {
		var tagger1 = WhitespaceTagger()
		let regions1 = tagger1.parseLine("@available(OSX 10.12, *)")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger1.stack.isEmpty)
	}
	
	func testHashAvailable() {
		var tagger1 = WhitespaceTagger()
		let regions1 = tagger1.parseLine("if #available(OSX 10.12, *) { print(\"Hi\") }")
		XCTAssert(regions1.isEmpty)
		XCTAssert(tagger1.stack.isEmpty)
	}
}
