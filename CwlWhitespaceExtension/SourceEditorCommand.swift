//
//  SourceEditorCommand.swift
//  CwlWhitespace
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

import Foundation
import XcodeKit

class SourceEditorCommand: NSObject, XCSourceEditorCommand {
   func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void) {
		// Limit changes when correcting to the selected range of lines
		var correctRange = 0..<invocation.buffer.lines.count
		if invocation.buffer.selections.count == 1, let s = invocation.buffer.selections.firstObject as? XCSourceTextRange, s.start.line != s.end.line || s.start.column != s.end.column {
			correctRange = s.start.line..<s.end.line + 1
		}
		
		let flagged = processLines(invocation.buffer.lines, usesTabs: invocation.buffer.usesTabsForIndentation, indentationWidth: invocation.buffer.indentationWidth, correctProblems: invocation.commandIdentifier == "com.cocoawithlove.whitespace.policingextension.correctProblems", limitToLines: correctRange)
		
		// Apply the new selection
		if !flagged.isEmpty {
			invocation.buffer.selections.setArray(flagged.map { tuple -> XCSourceTextRange in
				let result = XCSourceTextRange()
				result.start = XCSourceTextPosition(line: tuple.line, column: tuple.start)
				result.end = XCSourceTextPosition(line: tuple.line, column: tuple.end)
				return result
			})
		}
		
		completionHandler(nil)
	}
}
