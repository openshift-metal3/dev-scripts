import React, { useRef } from "react";
import { FaSpinner, FaCode } from "react-icons/fa";
import { SiEquinixmetal } from "react-icons/si";
import { BiError } from "react-icons/bi";
import { BsFileFont } from "react-icons/bs";

import Tooltips from "@material-tailwind/react/Tooltips";
import TooltipsContent from "@material-tailwind/react/TooltipsContent";
import TimeAgo from "react-timeago";

// HACK:
//
// tailwindcss scans your source files for class names, and if it finds its
// classes, it emits them in the final css bundle.  Since we're building the
// class names dynamically, the regex scanner doesn't recognize them.  Here, we
// create a list of classes we will produce with the `bg` function.
//
// eslint-disable-next-line
let css = ["bg-green-400", "bg-red-400", "bg-green-100", "bg-red-100"];

let bg = (build) => (build.new_build_in_progress ? "100" : "400");

let buildResultClassNames = (build) =>
  build.passed
    ? `bg-green-${bg(
        build
      )} dark:bg-green-800 hover:bg-green-300 dark:hover:bg-green-600 border-green-600`
    : `bg-red-${bg(
        build
      )} dark:bg-red-800 hover:bg-red-300 dark:hover:bg-red-600 border-red-600`;

let iconClasses = "inline mr-2 mt-1 absolute right-0";

let failureIcon = (build) => {
  switch (build.failure_reason) {
    case "baremetalds-devscripts-setup":
      return <FaCode className={iconClasses} />;
    case "baremetalds-e2e-test":
      return <BsFileFont className={iconClasses} />;
    case "baremetalds-packet-setup":
      return <SiEquinixmetal className={iconClasses} />;
    case "unknown":
      return <BiError className={iconClasses} />;
    default:
      return [];
  }
};

const Build = ({ build }) => {
  const ref = useRef();

  return (
    <>
      <div
        key={build.build_id}
        ref={ref}
        className={`p-1 px-3 border-2 rounded-lg w-72 relative ${buildResultClassNames(
          build
        )}`}
      >
        <a href={build.url} target="_blank" rel="noreferrer">
          {build.new_build_in_progress ? (
            <FaSpinner className="inline mr-2 animate-spin" />
          ) : (
            []
          )}
          {build.job_name}
        </a>
        {failureIcon(build)}
      </div>

      <Tooltips placement="left" ref={ref}>
        <TooltipsContent>
          Job finished: <TimeAgo date={build.finished} />
        </TooltipsContent>
      </Tooltips>
    </>
  );
};

export default Build;
