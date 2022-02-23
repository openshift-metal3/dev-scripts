.PHONY: prettier
prettier:
	./node_modules/.bin/prettier --write "src/**/*.{js,jsx}"

.PHONY: release
release:
	npm install
	npm run build
	go build -o metal-support cmd/metal-support.go
