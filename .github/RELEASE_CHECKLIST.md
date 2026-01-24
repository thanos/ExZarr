# Release Checklist for ExZarr v0.1.0

Use this checklist when preparing and publishing the release.

## Pre-Release Preparation

### Code Quality
- [x] All tests passing (`mix test`)
- [x] No Credo warnings (`mix credo --strict`)
- [x] Documentation up to date (`mix docs`)
- [x] No compiler warnings
- [x] Dependencies up to date

### Documentation
- [x] README.md updated with correct version
- [x] CHANGELOG.md contains v0.1.0 entry
- [x] RELEASE_NOTES.md created
- [x] INTEROPERABILITY.md reviewed and current
- [x] All code examples tested and working
- [x] API documentation complete with examples

### Version Numbers
- [ ] Update version in `mix.exs` (currently 0.1.0)
- [ ] Update version in README installation instructions
- [ ] Update version in documentation links
- [ ] Update CHANGELOG unreleased → 0.1.0

### Testing
- [x] Run full test suite: `mix test`
- [x] Run property tests: `mix test --only property`
- [x] Run Python integration tests: `mix test test/ex_zarr_python_integration_test.exs`
- [x] Test examples in documentation
- [x] Test interactive demo: `elixir examples/python_interop_demo.exs`

## Git and GitHub

### Git Tags
- [ ] Commit all changes
- [ ] Tag release: `git tag -a v0.1.0 -m "Release v0.1.0"`
- [ ] Push tag: `git push origin v0.1.0`
- [ ] Verify tag on GitHub

### GitHub Release
- [ ] Go to Releases → Draft a new release
- [ ] Select tag: v0.1.0
- [ ] Release title: "ExZarr v0.1.0 - Initial Release"
- [ ] Copy content from `.github/RELEASE_ANNOUNCEMENT.md`
- [ ] Add assets (if any):
  - [ ] Compiled docs (optional)
  - [ ] Examples archive (optional)
- [ ] Set as latest release
- [ ] Publish release

## Hex.pm Publication

### Prepare for Hex
- [ ] Review `mix.exs` package configuration
- [ ] Ensure LICENSE file exists
- [ ] Verify `files` list in `mix.exs` is correct
- [ ] Generate docs: `mix docs`
- [ ] Build package: `mix hex.build`
- [ ] Review package contents: `tar -tzf ex_zarr-0.1.0.tar`

### Publish to Hex
- [ ] Dry run: `HEX_API_KEY=your_key mix hex.publish --dry-run`
- [ ] Publish: `mix hex.publish`
- [ ] Confirm publication
- [ ] Wait for package to appear on Hex.pm
- [ ] Verify docs appear on HexDocs

### Post-Hex Publication
- [ ] Visit https://hex.pm/packages/ex_zarr
- [ ] Verify package info is correct
- [ ] Check documentation: https://hexdocs.pm/ex_zarr
- [ ] Test installation in new project

## Announcements

### Community Forums
- [ ] Post to Elixir Forum
  - [ ] Copy from `ANNOUNCEMENT_SHORT.md` (Elixir Forum section)
  - [ ] Include code examples
  - [ ] Link to docs and GitHub
  - [ ] Tag as "Show and Tell" or "Announcements"

- [ ] Post to Reddit r/elixir
  - [ ] Copy from `ANNOUNCEMENT_SHORT.md` (Reddit section)
  - [ ] Engage with comments

- [ ] Hacker News (optional, if appropriate timing)
  - [ ] Copy from `ANNOUNCEMENT_SHORT.md` (Hacker News section)
  - [ ] Monitor for discussion

### Social Media
- [ ] Twitter/X thread
  - [ ] Use thread from `ANNOUNCEMENT_SHORT.md`
  - [ ] Include screenshot or demo GIF
  - [ ] Tag #Elixir #DataScience #ScientificComputing

- [ ] LinkedIn (if applicable)
  - [ ] Professional announcement
  - [ ] Highlight business use cases

### Direct Outreach
- [ ] Notify Elixir Weekly: https://elixirweekly.net/submit
- [ ] Consider Elixir Radar: https://elixir-radar.com
- [ ] Elixir Status: https://elixirstatus.com/submit

## Documentation and Support

### Update Project Links
- [ ] Update GitHub repository description
- [ ] Add topics/tags to GitHub: elixir, zarr, arrays, data-science
- [ ] Ensure GitHub README displays correctly
- [ ] Add shields/badges to README (version, build status, etc.)

### Set Up Support Channels
- [ ] Monitor GitHub issues
- [ ] Set up issue templates (bug, feature request)
- [ ] Add CONTRIBUTING.md
- [ ] Add CODE_OF_CONDUCT.md
- [ ] Consider Discussions tab on GitHub

## Post-Release

### Monitoring
- [ ] Monitor Hex.pm download stats
- [ ] Watch for issues on GitHub
- [ ] Respond to community feedback
- [ ] Track forum discussions

### Follow-up
- [ ] Thank contributors (if any)
- [ ] Update project board with v0.2.0 goals
- [ ] Create milestone for v0.2.0
- [ ] Plan next features based on feedback

## Rollback Plan (If Needed)

If critical issues are discovered:

1. **Hex Package**
   - `mix hex.retire ex_zarr 0.1.0 --reason security`
   - Publish fixed version immediately

2. **GitHub Release**
   - Mark release as pre-release
   - Add warning banner to release notes
   - Create hotfix branch

3. **Communication**
   - Post update to all announcement channels
   - Update documentation with workarounds
   - Issue advisory if security-related

## Notes

- **Timing**: Consider publishing on weekday morning (UTC) for maximum visibility
- **Monitoring**: Plan to be available for questions on release day
- **Feedback**: Create tracking issue for v0.1.0 feedback

## Release Date

- **Target**: January 23, 2026
- **Released**: _____________
- **Released by**: _____________

---

## Post-Release Checklist

After 1 week:
- [ ] Review download statistics
- [ ] Respond to all issues/discussions
- [ ] Collect user feedback
- [ ] Update roadmap based on feedback
- [ ] Begin planning v0.2.0

After 1 month:
- [ ] Usage metrics review
- [ ] Identify most requested features
- [ ] Plan major features for v0.2.0
- [ ] Consider blog post with usage examples
