//
//  CwlWhitespaceCommand.swift
//  CwlWhitespace
//
//  Created by Matt Gallagher on 2016/06/25.
//  Copyright © 2016 Matt Gallagher. All rights reserved.
//

import Foundation

func processLines(_ mutableLines: NSMutableArray, usesTabs: Bool, indentationWidth: Int, correctProblems: Bool, limitToLines: CountableRange<Int>) -> [(line: Int, start: Int, end: Int)] {
	var flagged = [(line: Int, start: Int, end: Int)]()
	var tagger = WhitespaceTagger(indentationStyle: usesTabs ? .tabs : .spaces(indentationWidth))

	// Read the whole file
	for (lineIndex, lineContent) in mutableLines.enumerated() {
		if let line = lineContent as? String {
			// Perform the parse
			let taggedRegions = tagger.parseLine(line)
			
			// If the line has no issues, continue
			if taggedRegions.isEmpty {
				continue
			}
			
			if correctProblems {
				// Only edit the line if it's in the selection (or the selection was empty)
				if !limitToLines.contains(lineIndex) {
					continue
				}
				
				// Generate the corrected line
				let (corrected, selections) = apply(regions: taggedRegions, to: line, index: lineIndex, useTabs: usesTabs)

				// Apply
				flagged.append(contentsOf: selections)
				mutableLines.replaceObject(at: lineIndex, with: corrected)
			} else {
				if taggedRegions.first(where: { $0.start == $0.end }) != nil {
					// If any of the tagged regions are zero width (representing missing indent or whitespace), flag the whole line, since there's no other reasonable way to represent that.
					flagged.append((line: lineIndex, start: 0, end: line.unicodeScalars.count))
				} else {
					// Otherwise, flag the precise violating regions
					flagged.append(contentsOf: taggedRegions.map { (line: lineIndex, start: $0.start, end: $0.end) })
				}
			}
		}
	}
	
	return flagged
}

func apply(regions taggedRegions: [TaggedRegion], to line: String, index lineIndex: Int, useTabs: Bool) -> (String, [(line: Int, start: Int, end: Int)]) {
	// Build a "corrected" version of the line with replacements according to the expectations on "tagged" regions
	var corrected = ""
	let source = line.unicodeScalars
	var sourceIndex = source.startIndex
	var sourceCount = 0
	var offset = 0
	var added = false
	var flagged = [(line: Int, start: Int, end: Int)]()
	
	for region in taggedRegions {
		// Copy all text up to the start of the next region without modification
		while sourceCount > region.start {
			corrected.remove(at: corrected.index(corrected.endIndex, offsetBy: -1))
			sourceIndex = source.index(sourceIndex, offsetBy: -1)
			sourceCount -= 1
		}
		
		while sourceCount < region.start && sourceIndex != source.endIndex {
			corrected.append(source[sourceIndex])
			sourceIndex = source.index(after: sourceIndex)
			sourceCount += 1
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
			}
			
			// Generate a selection
			flagged.append((line: lineIndex, start: region.start - offset, end: region.start - offset + region.expected))
			added = true
		}
		
		// Skip over the corresponding region
		for _ in region.start..<region.end {
			sourceIndex = source.index(after: sourceIndex)
			sourceCount += 1
		}
		
		// Update the offset between the corrected and source text lines
		offset += region.end - region.start - region.expected
	}
	
	// Copy all text remaining up to the end of the line
	while sourceIndex != source.endIndex {
		corrected.append(source[sourceIndex])
		sourceIndex = source.index(after: sourceIndex)
	}
	
	// If we didn't generate any selections, select the whole line to indicate a change
	if !added {
		flagged.append((line: lineIndex, start: 0, end: corrected.unicodeScalars.count))
	}
	
	return (corrected, flagged)
}
