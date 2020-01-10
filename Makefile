
IN_VENV := PYTHONPATH=$$PYTHONPATH:fpr/ bash bin/in_venv.sh
FPR_PYTHON := $(IN_VENV) python fpr/run_pipeline.py

build-image:
	docker build -t fpr:build .

run-image:
	docker run --rm -i -v /var/run/docker.sock:/var/run/docker.sock --name fpr-test fpr:build python fpr/run_pipeline.py -v find_git_refs < tests/fixtures/mozilla_services_channelserver_repo_url.jsonl

run-repo-analysis-in-image:
	cat tests/fixtures/mozilla_services_channelserver_repo_url.jsonl | \
		docker run --rm -i -v /var/run/docker.sock:/var/run/docker.sock --name fpr-find_git_refs fpr:build python fpr/run_pipeline.py find_git_refs | \
		tee channelserver_tags.jsonl | \
		docker run --rm -i -v /var/run/docker.sock:/var/run/docker.sock --name fpr-cargo_metadata fpr:build python fpr/run_pipeline.py cargo_metadata | \
		tee channelserver_tags_metadata.jsonl | \
		docker run --rm -i -v /var/run/docker.sock:/var/run/docker.sock --name fpr-rust_changelog fpr:build python fpr/run_pipeline.py rust_changelog | \
		tee channelserver_changelog.jsonl

run-diff-repo-analysis-in-image:
	CIRCLE_SHA1=5a3e3967e90d65ca0d7a17b0466a3385898c3b6b printf "{\"org\": \"mozilla-services\", \"repo\": \"syncstorage-rs\", \"ref\": {\"value\": \"master\", \"kind\": \"branch\"}, \"repo_url\": \"https://github.com/mozilla-services/syncstorage-rs.git\"}\n{\"org\": \"mozilla-services\", \"repo\": \"syncstorage-rs\", \"ref\": {\"value\": \"5a3e3967e90d65ca0d7a17b0466a3385898c3b6b\", \"kind\": \"commit\"}, \"repo_url\": \"https://github.com/mozilla-services/syncstorage-rs.git\"}\n"  | \
	    docker run --rm -i -v /var/run/docker.sock:/var/run/docker.sock --name fpr-cargo_metadata fpr:build python fpr/run_pipeline.py cargo_metadata | \
	    docker run --rm -i -v /var/run/docker.sock:/var/run/docker.sock --name fpr-rust_changelog fpr:build python fpr/run_pipeline.py rust_changelog

check-channelserver-repo-analysis:
	test -f channelserver_tags.jsonl
	diff channelserver_tags.jsonl tests/fixtures/channelserver_tags.jsonl
	# TODO: check the metadata too or not since it'll change as deps update?
	test -f channelserver_changelog.jsonl
	# TODO: check for equivalent JSON output (changelog output needs work though)


install:
	bash ./bin/install.sh

install-dev:
	DEV=1 bash ./bin/install.sh

format:
	$(IN_VENV) black fpr/*.py fpr/**/*.py tests/**/*.py

type-check:
	$(IN_VENV) mypy fpr/

style-check:
	$(IN_VENV) pytest -v -o codestyle_max_line_length=120 --codestyle fpr/ tests/

shellcheck:
	shellcheck -s bash -x bin/*.sh

test:
	$(IN_VENV) pytest -vv --cov-branch --cov=fpr/ fpr/ tests/

unit-test: format style-check test type-check shellcheck

test-clear-cache:
	$(IN_VENV)  pytest --cache-clear -vv --cov-branch --cov=fpr/ fpr/ tests/

coverage: test
	$(IN_VENV) coverage html
	$(IN_VENV) python -m webbrowser htmlcov/index.html

clean:
	rm -rf htmlcov/ fpr-debug.log fpr-graph.png fpr-graph.svg output.dot
	docker stop $(shell docker ps -f "name=dep-obs-" -f "status=running" --format "{{.ID}}") || true
	docker container prune -f

run-fetch-package-data-and-save:
	printf '{"name":"123done"}\n{"name":"abab"}\n{"name":"abatar"}' | $(FPR_PYTHON) fetch_package_data --dry-run fetch_npmsio_scores
	printf '{"name":"123done"}\n{"name":"abab"}\n{"name":"abatar"}' | $(FPR_PYTHON) fetch_package_data fetch_npmsio_scores -o output.jsonl

run-find-git-refs:
	$(FPR_PYTHON) find_git_refs --keep-volumes -i tests/fixtures/mozilla_services_channelserver_repo_url.jsonl

run-find-git-refs-and-save:
	$(FPR_PYTHON) find_git_refs -i tests/fixtures/mozilla_services_channelserver_repo_url.jsonl -o output.jsonl

run-nodejs-metadata-and-save:
	printf '{"repo_url": "https://github.com/mozilla/fxa", "org": "mozilla", "repo": "fxa", "ref": {"value": "v1.153.0", "kind": "tag"},"versions": {"ripgrep": "ripgrep 11.0.2 (rev 3de31f7527)"},"dependency_file": {"path": "package.json", "sha256": "5a371f12ccff8f0f8b6e5f4c9354b672859f10b4af64469ed379d1b35f1ea584"}}\n{"repo_url": "https://github.com/mozilla/fxa", "org": "mozilla", "repo": "fxa", "ref": {"value": "v1.153.0", "kind": "tag"},"versions":{"ripgrep":"ripgrep 11.0.2 (rev 3de31f7527)"}, "dependency_file": {"path": "package-lock.json", "sha256": "665f4d2481d902fc36faffaab35915133a53f78ea59308360e96fb4c31f8b879"}}' \
		| $(FPR_PYTHON) nodejs_metadata --repo-task install --repo-task list_metadata --repo-task audit  --keep-volumes --dir './'  -o output.jsonl

run-crate-graph:
	$(FPR_PYTHON) -q crate_graph -i tests/fixtures/cargo_metadata_serialized.json | jq -r '.crate_graph_pdot' | dot -Tsvg > fpr-graph.svg
	$(IN_VENV) python -m webbrowser fpr-graph.svg

run-crate-graph-and-save:
	$(FPR_PYTHON) crate_graph -i tests/fixtures/cargo_metadata_serialized.json -o crate_graph.jsonl --dot-filename default.dot
	$(FPR_PYTHON) crate_graph -i tests/fixtures/cargo_metadata_serialized.json -a crate_graph.jsonl -o /dev/null --node-key name --node-label name_authors --filter dpc --filter serde --dot-filename serde_authors_filtered.dot
	$(FPR_PYTHON) crate_graph -i tests/fixtures/cargo_metadata_serialized.json -a crate_graph.jsonl -o /dev/null --node-key name --node-label name_authors --style 'dpc:color:red' --style 'serde:shape:box' --dot-filename graph-with-style-args.dot
	$(FPR_PYTHON) crate_graph -i tests/fixtures/cargo_metadata_serialized.json -a crate_graph.jsonl -o /dev/null --node-key name_version --node-label name_version_repository -g 'repository' --dot-filename groupby-repo.dot
	$(FPR_PYTHON) crate_graph -i tests/fixtures/cargo_metadata_serialized.json -a crate_graph.jsonl -o /dev/null --node-key name_version --node-label name_authors -g 'author' --dot-filename groupby-author.dot
	$(FPR_PYTHON) crate_graph -i tests/fixtures/cargo_metadata_serialized.json -a crate_graph.jsonl -o /dev/null --node-key name_version --node-label name_readme --dot-filename readme-node-label.dot
	$(FPR_PYTHON) crate_graph -i tests/fixtures/cargo_metadata_serialized.json -a crate_graph.jsonl -o /dev/null --node-key name_version --node-label name_repository --dot-filename repo-node-label.dot
	$(FPR_PYTHON) crate_graph -i tests/fixtures/cargo_metadata_serialized.json -a crate_graph.jsonl -o /dev/null --node-key name_version --node-label name_package_source --dot-filename source-node-label.dot
	$(FPR_PYTHON) crate_graph -i tests/fixtures/cargo_metadata_serialized.json -a crate_graph.jsonl -o /dev/null --node-key name_version --node-label name_metadata --dot-filename metadata-node-label.dot
	./bin/write_dotfiles.sh < crate_graph.jsonl

run-find-dep-files-and-save:
	printf '{"org": "mozilla", "repo": "fxa", "ref": {"value": "v1.142.0", "kind": "tag"}, "repo_url": "https://github.com/mozilla/fxa.git"}' | $(FPR_PYTHON) -v find_dep_files --keep-volumes -o output.jsonl

show-dot:
	dot -O -Tsvg *.dot
	./bin/open_svgs.sh

clean-graph:
	rm -f *.dot *.svg crate_graph.jsonl

run-cargo-audit:
	$(FPR_PYTHON) cargo_audit -i tests/fixtures/mozilla_services_channelserver_branch.jsonl
	$(FPR_PYTHON) cargo_audit -i tests/fixtures/mozilla_services_channelserver_tag.jsonl
	$(FPR_PYTHON) cargo_audit -i tests/fixtures/mozilla_services_channelserver_commit.jsonl

run-cargo-audit-and-save:
	$(FPR_PYTHON) cargo_audit -i tests/fixtures/mozilla_services_channelserver_branch.jsonl -o output.jsonl

run-cargo-metadata:
	$(FPR_PYTHON) cargo_metadata -i tests/fixtures/mozilla_services_channelserver_branch.jsonl

run-cargo-metadata-and-save:
	$(FPR_PYTHON) cargo_metadata -i tests/fixtures/mozilla_services_channelserver_branch.jsonl -o output.jsonl

run-crates-io-metadata-and-save:
	$(FPR_PYTHON) crates_io_metadata --db crates_io_metadata.db -i tests/fixtures/channelserver_tags_metadata.jsonl -o output.jsonl

run-github-metadata-and-save:
	printf "{\"repo_url\": \"https://github.com/mozilla/extension-workshop.git\"}" | $(FPR_PYTHON) github_metadata -i - -o output.jsonl --github-query-type=REPO_DEP_MANIFESTS --github-repo-dep-manifests-page-size=1 --github-query-type=REPO_DEP_MANIFEST_DEPS --github-repo-dep-manifest-deps-page-size=50 --github-query-type=REPO_VULN_ALERTS --github-repo-vuln-alerts-page-size=1 --github-query-type=REPO_VULN_ALERT_VULNS --github-repo-vuln-alert-vulns-page-size=1 --github-query-type=REPO_LANGS --github-repo-langs-page-size=50

run-cargo-metadata-fxa-and-save:
	$(FPR_PYTHON) cargo_metadata -i tests/fixtures/mozilla_services_fxa_branch.jsonl -o output.jsonl

run-rust-changelog:
	# run run-crates-io-metadata-and-save to have crates.io metadata available
	$(FPR_PYTHON) rust_changelog --db crates_io_metadata.db -i tests/fixtures/channelserver_tags_metadata.jsonl

run-rust-changelog-and-save:
	$(FPR_PYTHON) rust_changelog -i tests/fixtures/channelserver_tags_metadata.jsonl -o output.jsonl

run-repo-analysis:
	$(FPR_PYTHON) find_git_refs -i tests/fixtures/mozilla_services_channelserver_repo_url.jsonl -o mozilla_services_channelserver_tags.jsonl
	$(FPR_PYTHON) cargo_metadata -i mozilla_services_channelserver_tags.jsonl -o mozilla_services_channelserver_tags_metadata.jsonl
	$(FPR_PYTHON) rust_changelog -i mozilla_services_channelserver_tags_metadata.jsonl

integration-test: run-cargo-audit run-cargo-metadata run-crate-graph-and-save

# NB: assuming package names don't include spaces
update-requirements:
	bash ./bin/update_requirements.sh

dump-test-fixture-pickle-files:
	$(IN_VENV) python -m pickle tests/fixtures/*.pickle

venv-shell:
	$(IN_VENV) bash

.PHONY: build-image dump-test-fixture-pickle-files run-image coverage format type-check style-check test test-clear-cache clean install install-dev-tools run-crate-graph run-crate-graph-and-save run-cargo-audit run-cargo-audit-and-save run-cargo-metadata run-cargo-metadata-and-save run-crates-io-metadata-and-save run-github-metadata-and-save update-requirements show-dot integration-test run-find-git-refs run-find-git-refs-and-save publish-latest run-repo-analysis-in-image check-channelserver-repo-analysis run-diff-repo-analysis-in-image unit-test
