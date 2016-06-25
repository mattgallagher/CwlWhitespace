//
//  CwlWhitespaceCommandTests.swift
//  CwlWhitespace
//
//  Created by Matt Gallagher on 2016/06/24.
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

class CwlWhitespaceCommandTests: XCTestCase {
	func testProcessLines() {
		let lines = NSMutableArray()
		let selections = processLines(lines, usesTabs: true, indentationWidth: 4, correctProblems: true, limitToLines: 0..<1)
		XCTAssert(lines.count == 0)
		XCTAssert(selections.isEmpty)
	}

	func testDetect() {
		var lines = [String]()
		lines.append("//\tQuick  test")
		lines.append("dummy {")
		lines.append("not indented")
		lines.append("\tdouble  space")
		lines.append("}")
		let mutableLines = NSMutableArray(array: lines)
		let selections = processLines(mutableLines, usesTabs: true, indentationWidth: 4, correctProblems: false, limitToLines: 0..<1)
		XCTAssert(((mutableLines as [AnyObject]) as? [String])! == lines)
		XCTAssert(selections.count == 2)
		XCTAssert(selections[0] == (line: 2, start: 0, end: 12))
		XCTAssert(selections[1] == (line: 3, start: 7, end: 9))
	}

	func testCorrect() {
		var lines = [String]()
		lines.append("//\tQuick  test")
		lines.append("dummy {")
		lines.append("not indented")
		lines.append("\tdouble  space")
		lines.append("}")
		let mutableLines = NSMutableArray(array: lines)
		let selections = processLines(mutableLines, usesTabs: true, indentationWidth: 4, correctProblems: true, limitToLines: 3..<4)

		var lines2 = [String]()
		lines2.append("//\tQuick  test")
		lines2.append("dummy {")
		lines2.append("not indented")
		lines2.append("\tdouble space")
		lines2.append("}")

		XCTAssert(((mutableLines as [AnyObject]) as? [String])! == lines2)
		XCTAssert(selections.count == 1)
		XCTAssert(selections[0] == (line: 3, start: 7, end: 8))
	}
}
