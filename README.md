# CwlWhitespace

This project is written for Swift 3 and requires Xcode 8 to build.

The application is the delivery mechanism. Run the application once and the extension will be installed. *(If running Xcode 8 on El Capitan, you need to enable Xcode extensions. See the [Xcode 8 release notes](https://developer.apple.com/go/?id=xcode8-0-beta-release-notes) for more.)* To uninstall, drag the application to the Trash.

The extension itself has two commands, available from the "Whitespace Policing" submenu at the bottom of the "Editor" menu in Xcode when editing a source file:

* Detect problems
* Correct problems

*(There are some quirks in Xcode 8 beta 1 and sometimes the "Whitespace Policing" submenu will appear greyed out. To fix the problem, close all your projects and then quit Xcode. Upon reopening Xcode, wait on the "Welcome to Xcode" splash screen for about 5 seconds before opening your project.)*

The first command uses multiple selections to select every text range in your file that it believes is violating a whitespace rule. If a line contains a zero-length problem (missing whitespace or missing indent) then the whole line will be selected.

The second command edits whitespace problems to the expected values and selects the changed regions in your editor.

The tests in "CwlWhitespaceTaggingTests.swift" are the only documentation about what whitespace is permitted and what is disallowed.
