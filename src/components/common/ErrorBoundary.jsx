import React from 'react';
import { AlertTriangle, RefreshCw, RotateCcw } from 'lucide-react';

export class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError() {
    return { hasError: true };
  }

  componentDidCatch(error, info) {
    console.error('Our Space hit a rendering error:', error, info?.componentStack);
  }

  handleRetry = () => {
    this.setState({ hasError: false });
  };

  render() {
    if (!this.state.hasError) return this.props.children;

    return (
      <div className="min-h-screen flex items-center justify-center p-6 relative z-10">
        <div className="w-full max-w-sm bg-white/85 backdrop-blur rounded-3xl border border-blush-100 shadow-xl p-6 text-center">
          <div className="w-14 h-14 mx-auto rounded-full bg-amber-100 flex items-center justify-center">
            <AlertTriangle className="w-7 h-7 text-amber-500" />
          </div>

          <h2 className="mt-4 text-lg font-bold text-slate-800">
            Something went a bit wrong
          </h2>
          <p className="mt-2 text-xs leading-relaxed text-slate-500">
            This screen stopped drawing properly. Nothing has been lost — your memories are
            still saved on this phone.
          </p>

          <button
            type="button"
            onClick={this.handleRetry}
            className="mt-5 w-full inline-flex items-center justify-center gap-2 rounded-2xl bg-blush-400 px-4 py-3 text-sm font-bold text-white shadow-md shadow-blush-300/40 hover:bg-blush-500"
          >
            <RotateCcw className="w-4 h-4" />
            <span>Try again</span>
          </button>

          <button
            type="button"
            onClick={() => window.location.reload()}
            className="mt-2 w-full inline-flex items-center justify-center gap-2 rounded-2xl border border-slate-200 px-4 py-2.5 text-xs font-semibold text-slate-600 hover:bg-slate-50"
          >
            <RefreshCw className="w-3.5 h-3.5" />
            <span>Reload Our Space</span>
          </button>

          <p className="mt-3 text-[10px] leading-relaxed text-slate-400">
            Reloading will ask for your passphrase again, so try the first button first.
          </p>
        </div>
      </div>
    );
  }
}

export default ErrorBoundary;
