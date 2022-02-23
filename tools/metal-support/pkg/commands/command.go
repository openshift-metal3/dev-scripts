package commands

type Command interface {
	Run() error
}
