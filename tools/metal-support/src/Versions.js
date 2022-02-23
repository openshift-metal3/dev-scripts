import React, { Component } from "react";
import Version from "./Version";

class Versions extends Component {
  render() {
    return this.props.loaded ? (
      <div className="flex flex-row items-stretch gap-4 w-full p-3">
        {this.props.versions.map((version) => (
          <Version key={version.name} version={version} />
        ))}
      </div>
    ) : (
      <div className="text-xl p-20 text-center">
        <h3>Nothing to show yet</h3>
      </div>
    );
  }
}

export default Versions;
