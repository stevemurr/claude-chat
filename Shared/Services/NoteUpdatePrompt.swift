import Foundation

enum NoteUpdatePrompt {
    static let instructions = """
    [The user has attached notes for reference. ONLY update notes if explicitly asked.

    Operations:
    APPEND:       <note-update date="YYYY-MM-DD" op="append">new content</note-update>
    PREPEND:      <note-update date="YYYY-MM-DD" op="prepend">new content</note-update>
    REPLACE-ALL:  <note-update date="YYYY-MM-DD" op="replace-all">complete new content</note-update>
    REPLACE:      <note-update date="YYYY-MM-DD" op="replace" match="exact text">replacement</note-update>
    DELETE:       <note-update date="YYYY-MM-DD" op="delete" match="exact text to remove" />
    INSERT-AFTER: <note-update date="YYYY-MM-DD" op="insert-after" match="text to insert after">new content</note-update>

    Rules:
    - date MUST match the (date: ...) shown for the note
    - match must be an EXACT substring from the note
    - Prefer append/prepend/insert-after over replace-all to preserve existing content
    - Only use replace-all when user asks to completely rewrite the note]
    """
}
