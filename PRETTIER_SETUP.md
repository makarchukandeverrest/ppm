# Prettier Setup Guide

## ✅ Prettier is now configured and working!

### What's been set up:

1. **Prettier Configuration** (`.prettierrc`)
    - Configured for JavaScript, HTML, CSS, JSON, XML, and YAML files
    - 120 character line width
    - 4-space indentation
    - Single quotes for strings
    - Semicolons enabled

2. **VS Code Integration** (`.vscode/settings.json`)
    - Format on save enabled
    - Prettier as default formatter
    - ESLint integration

3. **Ignore File** (`.prettierignore`)
    - Excludes Salesforce metadata files
    - Excludes build outputs and logs

### How to use Prettier:

#### 1. **Format all files at once:**

```bash
npm run prettier
```

#### 2. **Check formatting without changing files:**

```bash
npm run prettier:verify
```

#### 3. **Format specific files:**

```bash
npx prettier --write "path/to/file.js"
```

#### 4. **VS Code Auto-formatting:**

- Files will automatically format when you save (Ctrl+S)
- You can also use Shift+Alt+F to format manually

### Supported File Types:

- ✅ JavaScript (.js)
- ❌ LWC/Aura HTML (.html) - Lightning Web Component syntax not compatible with Prettier
- ✅ CSS (.css)
- ✅ JSON (.json)
- ✅ XML (.xml)
- ✅ YAML (.yml, .yaml)
- ✅ Markdown (.md)
- ❌ Apex (.cls, .trigger) - Not supported by prettier-plugin-apex

### Notes:

- Apex files (.cls, .trigger) are excluded from Prettier formatting due to parser issues
- All other Salesforce files (LWC, HTML, CSS, JS) are fully supported
- The configuration is optimized for Salesforce development

### VS Code Extensions Required:

- Prettier - Code formatter (esbenp.prettier-vscode)
- ESLint (dbaeumer.vscode-eslint)

Your Prettier setup is complete and ready to use! 🎉
