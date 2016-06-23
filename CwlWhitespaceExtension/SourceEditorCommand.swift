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
	func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: (NSError?) -> Void ) -> Void {
		var flagged = [XCSourceTextRange]()
		var tagger = WhitespaceTagger(indentationStyle: invocation.buffer.usesTabsForIndentation ? .tabs : .spaces(invocation.buffer.indentationWidth))

		let correct = invocation.commandIdentifier == "com.cocoawithlove.whitespace.policingextension.correctProblems"
		var correctRange = 0..<invocation.buffer.lines.count

		// Limit changes when correcting to the selected range of lines
		if invocation.buffer.selections.count == 1, let s = invocation.buffer.selections.firstObject as? XCSourceTextRange where s.start.line != s.end.line || s.start.column != s.end.column {
			correctRange = s.start.line..<s.end.line + 1
		}
		
		// Read the whole file
		for (lineIndex, lineContent) in invocation.buffer.lines.enumerated() {
			if let line = lineContent as? String {
			
				// Perform the parse
				let taggedRegions = tagger.parse(line: line)
				
				// If the line has no issues, continue
				if taggedRegions.isEmpty {
					continue
				}
				
				if correct {
					// Only edit the line if it's in the selection (or the selection was empty)
					if !correctRange.contains(lineIndex) {
						continue
					}
					
					// Generate the corrected line
					let (corrected, selections) = apply(regions: taggedRegions, to: line, index: lineIndex, useTabs: invocation.buffer.usesTabsForIndentation)

					// Apply
					flagged.append(contentsOf: selections)
					invocation.buffer.lines.replaceObject(at: lineIndex, with: corrected)
				} else {
					if taggedRegions.first(where: { $0.start == $0.end }) != nil {
						// If any of the tagged regions are zero width (representing missing indent or whitespace), flag the whole line, since there's no other reasonable way to represent that.
						flagged.append(textRange(line: lineIndex, start: 0, end: line.unicodeScalars.count))
					} else {
						// Otherwise, flag the precise violating regions
						flagged.append(contentsOf: taggedRegions.map { $0.textRange(for: lineIndex) })
					}
				}
			}
		}
		
		// Apply the new selection
		if !flagged.isEmpty {
			invocation.buffer.selections.setArray(flagged)
		}
		
		completionHandler(nil)
	}
}

// It would be better to make this an extension on XCSourceTextRange but that's causing runtime errors in Xcode 8 beta 1
func textRange(line: Int, start: Int, end: Int) -> XCSourceTextRange {
	let result = XCSourceTextRange()
	result.start = XCSourceTextPosition(line: line, column: start)
	result.end = XCSourceTextPosition(line: line, column: end)
	return result
}

func apply(regions taggedRegions: [TaggedRegion], to line: String, index lineIndex: Int, useTabs: Bool) -> (String, [XCSourceTextRange]) {
	// Build a "corrected" version of the line with replacements according to the expectations on "tagged" regions
	var corrected = ""
	var sourceIterator = line.unicodeScalars.makeIterator()
	var sourceIndex = 0
	var offset = 0
	var added = false
	var flagged = [XCSourceTextRange]()
	
	for region in taggedRegions {
		// Copy all text up to the start of the next region without modification
		while sourceIndex < region.start - offset, let s = sourceIterator.next() {
			corrected.append(s)
			sourceIndex += 1
		}
		
		// Generate a new region, replacing the tagged region
		if region.expected > 0 {
			let correctionScalar: UnicodeScalar
			if region.tag == .incorrectIndent && useTabs {
				correctionScalar = "\t"
			} else {
				correctionScalar = " "
			}
			
			// Write the corrected whitespace
			for _ in 0..<(region.expected) {
				corrected.append(correctionScalar)
				sourceIndex += 1
			}
			
			// Generate a selection
			flagged.append(textRange(line: lineIndex, start: region.start - offset, end: region.start - offset + region.expected))
			added = true
		}
		
		// Skip over the corresponding region
		for _ in region.start..<region.end {
			_ = sourceIterator.next()
		}
		
		// Update the offset between the corrected and source text lines
		offset = region.end - region.start - region.expected
	}
	
	// Copy all text remaining up to the end of the line
	while let s = sourceIterator.next() {
		corrected.append(s)
	}
	
	// If we didn't generate any selections, select the whole line to indicate a change
	if !added {
		flagged.append(textRange(line: lineIndex, start: 0, end: corrected.unicodeScalars.count))
	}
	
	return (corrected, flagged)
}

extension TaggedRegion {
	func textRange(for line: Int) -> XCSourceTextRange {
		let tr = XCSourceTextRange()
		tr.start = XCSourceTextPosition(line: line, column: start)
		tr.end = XCSourceTextPosition(line: line, column: end)
		return tr
	}
}
