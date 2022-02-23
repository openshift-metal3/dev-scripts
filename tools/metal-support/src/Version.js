import React, { Component } from "react";

import Builds from "./Builds";

class Version extends Component {
  render() {
    let version = this.props.version;
    let informing = version.builds.filter(
      (build) => build.type === "informing"
    );
    let blocking = version.builds.filter((build) => build.type === "blocking");
    let upgrade = version.builds.filter((build) => build.type === "upgrade");
    return (
      <div className="p-8 bg-white dark:bg-slate-800 rounded-lg shadow-lg font-mono">
        <h1 className="text-center font-bold text-4xl text-slate-600 dark:text-slate-200 mb-5">
          {version.name}
        </h1>

        <Builds type="Blocking" builds={blocking} />
        <Builds type="Informing" builds={informing} />
        <Builds type="Upgrade" builds={upgrade} />
      </div>
    );
  }
}

export default Version;
