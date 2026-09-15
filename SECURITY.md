# Security

The gates in this repository intercept commands before they run and decide whether a push, a write or a session stop goes through. A way past a gate without the declared escape is a vulnerability of this project and not a bug, and three were found and closed on the day this file was written, each with a control that was red first.

## Reporting

Use the private vulnerability reporting of this repository on GitHub, under the Security tab, and never a public issue. Include the command or the payload that opens the gate, the gate it opens, and what the receipt recorded. A report with a reproduction gets a control written for it before the fix, and the control is named in the release notes.

## In scope

Any input that makes a gate exit 0 when the method says it must block, any input that records `escaped` in the receipt without the escape token at the head of a segment, and any path where a gate certifies a result it did not measure.

## Out of scope

The gates are advisory on a machine you control, and the escapes exist on purpose. Declaring an escape is not a bypass.
