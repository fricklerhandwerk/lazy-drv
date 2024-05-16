{ writeShellApplication, git, nixdoc, busybox, perl }:
{ category, description, file, output }:
writeShellApplication {
  name = "nixdoc-to-github";
  runtimeInputs = [ nixdoc busybox perl ];
  # nixdoc makes a few assumptions that are specific to the Nixpkgs manual.
  # Those need to be adapated to GitHub Markdown:
  # - Turn `:::{.example}` blocks into block quotes
  # - Remove section anchors
  # - GitHub produces its own anchors, change URL fragments accordingly
  text = ''
    nixdoc --category "${category}" --description "${description}" --file "${file}" | awk '
    BEGIN { p=0; }
    /^\:\:\:\{\.example\}/ { print "> **Example**"; p=1; next; }
    /^\:\:\:/ { p=0; next; }
    p { print "> " $0; next; }
    { print }
    ' | sed 's/[[:space:]]*$//' \
      | sed 's/ {#[^}]*}//g' \
      | sed "s/\`\`\` /\`\`\`/g" \
      | sed 's/function-library-//g' | perl -pe 's/\(#([^)]+)\)/"(#" . $1 =~ s|\.||gr . ")" /eg' \
      > "${output}"
  '';
}
