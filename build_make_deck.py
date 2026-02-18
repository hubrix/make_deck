#!/usr/bin/env python3

"""
Script to build the standalone make_deck executable by embedding templates.
"""

import sys
import os

def main():
    # Read the template script
    with open('make_deck.template.sh', 'r') as f:
        template_content = f.read()
    
    # Read the simple beamer LaTeX template
    with open('pandoc/templates/simple_beamer.latex', 'r') as f:
        simple_template = f.read()

    # Read the PPTX theme extractor script
    with open('scripts/extract_pptx_theme.py', 'r') as f:
        extractor_content = f.read()

    # Replace placeholders
    result = template_content.replace('__SIMPLE_BEAMER_CONTENT__', simple_template)
    result = result.replace('__EXTRACT_PPTX_THEME_CONTENT__', extractor_content)
    
    # Write to make_deck
    with open('make_deck.new', 'w') as f:
        f.write(result)
    
    # Make it executable
    os.chmod('make_deck.new', 0o755)
    
    # Check if it changed
    try:
        with open('make_deck', 'r') as f:
            existing = f.read()
        if existing == result:
            print("make_deck is already up to date")
            os.remove('make_deck.new')
            return
    except FileNotFoundError:
        pass
    
    # Replace the old file
    os.rename('make_deck.new', 'make_deck')
    print("Updated make_deck executable")

if __name__ == '__main__':
    main()