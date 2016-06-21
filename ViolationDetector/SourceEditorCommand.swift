//
//  SourceEditorCommand.swift
//  ViolationDetector
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
	func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: (NSError?) -> Void ) -> Void {
		var flagged = [XCSourceTextRange]()
		var stack: [TaggedRegion] = [TaggedRegion(line: 0, start: 0, end: 0, tag: .indent)]
		for (lineIndex, lineContent) in invocation.buffer.lines.enumerated() {
			if let l = lineContent as? String {
				var scanner = ScalarScanner(scalars: l.unicodeScalars, context: ParseContext(line: lineIndex, stack: stack))
				do {
					try scanner.parseLine()
					let textRanges = scanner.context.flagged.map { $0.textRange() }
					flagged.append(contentsOf: textRanges)
				} catch {
					let range = XCSourceTextRange()
					range.start = XCSourceTextPosition(line: lineIndex, column: 0)
					range.end = XCSourceTextPosition(line: lineIndex, column: l.unicodeScalars.count)
					flagged.append(range)
				}
				stack = scanner.context.stack
			}
		}
		
		if !flagged.isEmpty {
			invocation.buffer.selections.setArray(flagged)
		}
		
		completionHandler(nil)
	}
}

extension TaggedRegion {
	func textRange() -> XCSourceTextRange {
		let tr = XCSourceTextRange()
		tr.start = XCSourceTextPosition(line: line, column: start)
		tr.end = XCSourceTextPosition(line: line, column: end)
		return tr
	}
}
