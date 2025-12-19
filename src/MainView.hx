package ;

import haxe.ui.containers.dialogs.Dialog.DialogEvent;
import haxe.ui.containers.dialogs.Dialog.DialogButton;

import haxe.ui.containers.dialogs.MessageBox;
import haxe.ui.containers.VBox;
import haxe.ui.events.MouseEvent;

@:build(haxe.ui.ComponentBuilder.build("assets/main-view.xml"))
class MainView extends VBox {
    public function new() {
        super();
        button1.onClick = function(e) {
            button1.text = "Go Google?";
            mywebview.url = "https://google.com";
        }
    }
    
    @:bind(button2, MouseEvent.CLICK)
    private function onMyButton(e:MouseEvent) {
        mywebview.getPageObject("document.title",(res:String)-> {
            trace("Title: " + res);
            button2.text = res;
        });
    }
    @:bind(button3, MouseEvent.CLICK)
    private function button3fnc(e:MouseEvent) {
        mywebview.getPageObject("document.body.innerHTML", (res:String)-> {
            var msg = new MessageBox();
            msg.title = "Alert";
            msg.text = res;
            msg.buttons = DialogButton.OK; // Single OK button
            msg.onDialogClosed = function(event:DialogEvent) {
                if (event.button == DialogButton.OK) {
                    trace("User pressed OK");
                }               
            };
            msg.showDialog();
        });
    }
}