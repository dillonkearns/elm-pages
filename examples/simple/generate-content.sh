#!/bin/bash

cd content
for i in {1..1000}
do
   echo -e "---\ntitle: Post Number\ntype: page\n---\n\n## Page $i\n\nWelcome to page $i" > "page-$i.md"
done