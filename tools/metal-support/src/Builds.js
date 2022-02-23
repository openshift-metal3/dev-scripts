import React, { Component } from "react";
import Build from "./Build";

export default class Builds extends Component {
  render() {
    return (
      <div className="text-sm grid gap-2 mb-4 dark:text-slate-300">
        <h3>{this.props.type}</h3>
        {this.props.builds.map((build) => (
          <Build build={build} />
        ))}
      </div>
    );
  }
}
