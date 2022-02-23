import React, { Component } from "react";
import { GiGuitar, GiBearFace } from "react-icons/gi";
import axios from "axios";

import Versions from "./Versions";
import ColorToggle from "./ColorToggle";

class Loader extends Component {
  render() {
    return (
      <div className="inline-flex items-center text-slate-600">
        <svg className="animate-spin h-5 w-5 mr-3" viewBox="0 0 24 24">
          <circle
            className="opacity-25"
            cx="12"
            cy="12"
            r="10"
            stroke="currentColor"
            strokeWidth="4"
          ></circle>
          <path
            className="opacity-75"
            fill="currentColor"
            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
          ></path>
        </svg>
        <h1 className="text-lg p-3 text-slate-400">Loading...</h1>
      </div>
    );
  }
}

export default class App extends Component {
  state = {
    versions: [],
    loaded: false,
    lastUpdated: null,
    updating: false,
  };

  componentDidMount() {
    this.fetchData();
    this.timer = setInterval(() => this.fetchData(), 60 * 1000);
  }

  fetchData() {
    this.setState({ updating: true });

    axios.get(`/data.json`).then((res) => {
      const versions = res.data.versions;
      const lastUpdated = res.data.last_updated;
      this.setState({ versions, lastUpdated, loaded: true, updating: false });
    });
  }

  render() {
    return (
      <div className="bg-slate-100 dark:bg-slate-600 font-mono min-h-screen">
        <div className="bg-white dark:bg-slate-800 mb-1 h-10 h-12 text-slate-800 dark:text-slate-100 flex justify-between">
          <div className="">
            <h1 className="text-lg p-3">
              <GiBearFace className="inline" />
              <GiGuitar className="inline mr-3" />
              Metal Wall (nightly stream jobs)
            </h1>
          </div>
          {this.state.updating ? <Loader /> : []}
          <ColorToggle />
        </div>

        <Versions loaded={this.state.loaded} versions={this.state.versions} />

        <div className="text-xs text-center text-slate-400 mt-10">
          <p>Last updated {this.state.lastUpdated}</p>
        </div>
      </div>
    );
  }
}
