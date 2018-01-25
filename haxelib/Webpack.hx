#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
using haxe.io.Path;
using StringTools;
#end

class Webpack {
	/**
	 * JavaScript `require` function, for synchronous module loading
	 */
	public static macro function require(file:String):ExprOf<Dynamic> {
		if (Context.defined('js')) {
			// Adjust relative path
			// TODO: handle inline loader syntax
			if (file.startsWith('.')) {
				var posInfos = Context.getPosInfos(Context.currentPos());
				var directory = posInfos.file.directory();
				file = rebaseRelativePath(directory, file);
			}
			return macro js.Lib.require($v{file});
		} else {
			// TODO: find a way to track "required" files on non-JS builds.
			// Perhaps by tracking in metadata and saving to the JSON outputFile, and processng inside the loader.
			return macro null;
		}
	}

	/**
	 * Load a Haxe class asynchronously, using haxe-modular code splitting to separate it from the main bundle.
	 *
	 * This will use `System.import()` to have webpack load it asynchronously.
	 *
	 * @param classRef The Haxe class or type you wish to load asynchronously
	 * @return A `js.Promise` that will complete when the module is loaded. See README for information on how to use.
	 */
	public static macro function load(classRef:Expr) {
		switch (Context.typeof(classRef)) {
			case haxe.macro.Type.TType(_.get() => t, _):
				var module = t.module.split('.').join('_');
				var query = resolveModule(module);
				var link = macro untyped $i{module} = $p{["$s", module]};
				return macro {
					#if debug
					if (untyped module.hot) {
						untyped module.hot.accept($v{query}, function() {
							untyped require($v{query});
							$link;
						});
					}
					#end
					untyped __js__('System.import')($v{query})
						.then(function(exports) {
							$link;
							var _ = untyped $i{module}; // forced reference
							return exports;
						});
				}
			default:
		}
		Context.fatalError('A module class reference is required', Context.currentPos());
		return macro {};
	}

	/**
	 * Load a manually controlled bundle using it's bundle identifier.
	 *
	 * With haxe-modular it is possible to manually control which modules are split into separate bundles.
	 * This is useful if your project makes heavy use of reflection, which will limit the effectiveness of
	 * automatic code-splitting. See https://github.com/elsassph/haxe-modular/blob/master/doc/advanced.md#controlled-bundling
	 *
	 * @param name The unique name of the manually configured haxe-modular bundle you wish to load. Must be a constant string.
	 * @return A `js.Promise` that will resolve with the loaded module. See the link above for details on usage.
	 */
	public static macro function loadModule(name:Expr) {
		switch (name.expr) {
			case EConst(CString(module)):
				var query = resolveModule(module);
				return macro untyped __js__('System.import')($v{query});
			default:
		}
		Context.fatalError('A String literal is required', Context.currentPos());
		return macro {};
	}

	#if macro
	static function resolveModule(name:String) {
		var ns = Context.definedValue('webpack_namespace');
		return '!haxe-loader?$ns/$name!';
	}

	static function rebaseRelativePath(directory:String, file:String) {
		// make base path relative
		if (~/^(\/)|([A-Z]:)/i.match(directory)) {
			var cwd = Sys.getCwd().replace('\\', '/');
			if (directory.startsWith(cwd))
				directory = './${directory.substr(cwd.length)}';
		}

		if (file.startsWith('./')) {
			file = file.substr(2);
			return './${directory}/${file}';
		}

		while (file.startsWith('../')) {
			if (directory.indexOf('/') > 0) {
				file = file.substr(3);
				directory = directory.directory();
			} else if (directory != '') {
				file = file.substr(3);
				directory = '';
				break;
			}
		}

		if (directory != '') {
			return './${directory}/${file}';
		}
		if (file.startsWith('.')) {
			// file goes further up the project root
			return file;
		}
		return './${file}';
	}
	#end
}
