#!/usr/bin/env python3
import os
import re
from pathlib import Path

# Pattern to match .withValues(alpha: value)
pattern = r'\.withValues\(alpha:\s*([0-9.]+)\)'
replacement = r'.withOpacity(\1)'

def fix_dart_file(filepath):
    """Fix .withValues(alpha: X) to .withOpacity(X) in a Dart file"""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Check if file has withValues
    if '.withValues(alpha:' not in content:
        return False
    
    # Replace the pattern
    updated_content = re.sub(pattern, replacement, content)
    
    # Write back if changed
    if content != updated_content:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(updated_content)
        return True
    
    return False

def main():
    # Find all Dart files in lib directory
    lib_dir = Path('agos_app/lib')
    dart_files = list(lib_dir.rglob('*.dart'))
    
    fixed_count = 0
    for dart_file in dart_files:
        if fix_dart_file(str(dart_file)):
            print(f"Fixed: {dart_file}")
            fixed_count += 1
    
    print(f"\nTotal files fixed: {fixed_count}")

if __name__ == '__main__':
    main()
