-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

package data_structures is
    type linked_list is protected
  
       procedure push(constant c_data : in integer);
       impure function pop return integer;
       impure function is_empty return boolean;
  
    end protected;
  end package data_structures;
  
  package body data_structures is
  
    type linked_list is protected body
  
       type item_t;
       type ptr_t is access item_t;
       type item_t is record
          data : integer;
          next_item : ptr_t;
       end record;
  
       variable root : ptr_t;
  
       procedure push( constant c_data : in integer) is
          variable v_new_item : ptr_t;
          variable v_node : ptr_t;
       begin
          v_new_item := new item_t;
          v_new_item.data := c_data;
  
          if root = null then
             root := v_new_item;
  
          else
             v_node := root;
  
             while v_node.next_item /= null loop
                v_node := v_node.next_item;
             end loop;
  
             v_node.next_item := v_new_item;
          end if;
       end;
  
       impure function pop return integer is
          variable v_node : ptr_t;
          variable v_retval : integer;
       begin
          v_node := root;
          root := root.next_item;
  
          v_retval := v_node.data;
          deallocate(v_node);
  
          return v_retval;
       end;
  
       impure function is_empty return boolean is
       begin
          return root = null;
       end;
  
    end protected body;
  
  end package body data_structures;